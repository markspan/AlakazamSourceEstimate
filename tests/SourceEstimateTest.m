classdef SourceEstimateTest < matlab.unittest.TestCase
%SOURCEESTIMATETEST  Source Estimate: the noise model it resolves and uses,
%   and the stored estimate, which must equal an independent inverse and
%   be reused by the source cluster test only when it may be.
%
%   The noise-model cases run on synthetic subjects with a standard 10-20
%   montage, through the real template forward model (the 5124-vertex
%   sheet, to stay quick). The Slow cases need two comparable subject
%   averages of the BCN2025 study under Cache in the data folder
%   (ALAKAZAM_DATA, Alakazam's Data folder, or D:\data), and skip without
%   them. Everything needs FieldTrip, and skips without it.
%
%   The checks on the store itself, its key, its fingerprint and the
%   cropping of a stored estimate, are Alakazam's (SourceCacheTest there),
%   as is the cluster test's choice of one noise model for every subject
%   (SourceNoiseModelTest).
%
%   Run with: runtests('tests/SourceEstimateTest.m').
%
%   See also SOURCEESTIMATE, SOURCECLUSTERSTATS.

    properties (Constant)
        Labels = {'Fp1', 'Fp2', 'F7', 'F3', 'Fz', 'F4', 'F8', 'T7', 'C3', 'Cz', ...
                  'C4', 'T8', 'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'O2'}
    end

    properties
        Alakazam = ''   % Alakazam's source folder, which the plugin runs in
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            plugin = fileparts(fileparts(mfilename('fullpath')));
            root = getenv('ALAKAZAM_ROOT');   % Alakazam's source, which the plugin runs in
            if isempty(root)
                root = fullfile(fileparts(plugin), 'Alakazam');
            end
            testCase.assumeTrue(isfolder(fullfile(root, 'src')), ...
                'Alakazam''s source is not found (set ALAKAZAM_ROOT).');
            testCase.Alakazam = root;
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(plugin, 'tests')));
            for p = {fullfile(root, 'src'), fullfile(root, 'src', 'Support'), ...
                     fullfile(root, 'src', 'Reports'), fullfile(root, 'src', 'Transformations'), ...
                     fullfile(root, 'src', 'Transformations', 'Average'), ...
                     fullfile(plugin, 'SourceEstimate'), ...
                     fullfile(root, 'tests', 'fixtures')}
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(p{1}));
            end
        end

        function requireFieldTrip(testCase)
            FieldTripFixtures.require(testCase);
        end
    end

    methods (Test)
        % ---- the noise model --------------------------------------------
        function sourceEstimateUsesTheBaselineWhenItCan(testCase)
            avg = testCase.subjectAverage(1);
            withNoise = FieldTripFixtures.quietly(@() SourceEstimate(avg, testCase.estimateOpts('auto')));
            stored = withNoise.sourceEstimate(end);
            testCase.verifyEqual(stored.key.noiseModel, 'baseline');
            testCase.verifyEqual(stored.key.snr, 3);
            testCase.verifyEqual({stored.info.noiseModel}, {'baseline', 'baseline'});

            white = FieldTripFixtures.quietly(@() SourceEstimate(avg, testCase.estimateOpts('identity')));
            whiteStored = white.sourceEstimate(end);
            testCase.verifyEqual(whiteStored.key.noiseModel, 'identity');
            testCase.verifyGreaterThan(max(abs(stored.values(:) - whiteStored.values(:))), 0, ...
                'The two noise models give different estimates.');

            sl = FieldTripFixtures.quietly(@() SourceEstimate(avg, ...
                testCase.estimateOpts('auto', 'Method', 'sloreta')));
            testCase.verifyEqual(sl.sourceEstimate(end).key.noiseModel, 'identity', ...
                'sLORETA does not use it, and its key says so.');
        end

        function aDatasetWithoutOneFallsBackOrRefuses(testCase)
            avg = testCase.subjectAverage(1);
            avg.noiseCov = [];
            auto = FieldTripFixtures.quietly(@() SourceEstimate(avg, testCase.estimateOpts('auto')));
            testCase.verifyEqual(auto.sourceEstimate(end).key.noiseModel, 'identity');
            testCase.verifyError(@() FieldTripFixtures.quietly(@() ...
                SourceEstimate(avg, testCase.estimateOpts('baseline'))), 'Alakazam:SourceEstimate');
        end
    end

    methods (Test, TestTags = {'Slow'})
        function theStoredEstimateMatchesAnIndependentInverse(testCase)
        %THESTOREDESTIMATEMATCHESANINDEPENDENTINVERSE  The check that the
        %   store's own tests cannot make.
        %
        %   Comparing SourceEstimate against SourceClusterStats only shows
        %   that two paths agree, and they can agree by sharing a mistake.
        %   They did: both indexed the channel reorder into the wrong array,
        %   so both selected the same wrong channels, and an equivalence
        %   test between them passed with a maximum difference of exactly
        %   zero while the estimates were computed from EOG.
        %
        %   So this reproduces the inverse from first principles -- select
        %   the scalp channels, reorder to the forward model, invert -- and
        %   demands the stored values equal it. It is deliberately written
        %   without reusing the production helpers that do the selecting.
            files = testCase.comparableSubjects();
            testCase.assumeNotEmpty(files, 'No comparable subject averages available.');

            settings = struct('Method', 'mne', 'Orientation', 'normal', ...
                'SourceSpace', 5124, 'TimeWindow', [250 400], ...
                'ResampleHz', 100, 'RegParam', 0.05);
            loaded = load(files{1}, 'EEG');
            stored = FieldTripFixtures.quietly(@() SourceEstimate(loaded.EEG, settings));

            resolved = FieldTripFixtures.quietly(@() ...
                TransTools.ResolveScalpDistribution(loaded.EEG, 'Alakazam:SourceEstimateTest'));
            scalpLabels = {resolved.ScalpChanlocs.labels};
            [leadfield, sourcemodel, modelLabels, elec, headmodel] = ...
                FieldTripFixtures.quietly(@() ...
                    TransTools.BuildSourceForwardModel(scalpLabels, settings.SourceSpace));

            [present, reorder] = ismember(lower(modelLabels), lower(scalpLabels));
            testCase.assertTrue(all(present));

            % Scalp channels first, THEN the forward model's order. Doing it
            % in one step is the bug this test exists for.
            scalpData = resolved.data(resolved.ScalpHasPos, :, 1);
            values = double(scalpData(reorder, :));
            times = reshape(resolved.times, 1, []);
            [values, ~] = TransTools.RestrictAndDecimate(values, times, ...
                settings.TimeWindow, settings.ResampleHz, 'Alakazam:SourceEstimateTest');

            solveOpts = struct('RegParam', settings.RegParam, ...
                'Orientation', 'normal', ...
                'Normals', TransTools.SurfaceNormals(sourcemodel));
            expected = FieldTripFixtures.quietly(@() TransTools.InverseSolution( ...
                values, leadfield, elec, headmodel, settings.Method, solveOpts));

            firstBin = stored.sourceEstimate.bins{1};
            key = SourceCache.Key(modelLabels, settings);
            actual = SourceCache.Lookup(stored, firstBin, key);

            testCase.assertNotEmpty(actual, 'The stored estimate was not retrievable.');
            testCase.verifyEqual(actual, expected, ...
                'The stored estimate does not match an independently computed inverse.');
        end

        function anEstimateIsReusedAndChangesNothing(testCase)
        %ANESTIMATEISREUSEDANDCHANGESNOTHING  The claim the whole feature
        %   rests on: a reused estimate must give the SAME answer as a
        %   computed one. Compared on the observed statistic, which is
        %   deterministic; the p-values cannot be compared because the
        %   permutations are drawn afresh each run.
            files = testCase.comparableSubjects();
            testCase.assumeNotEmpty(files, 'No two comparable subject averages available.');

            settings = struct('Method', 'mne', 'Orientation', 'normal', ...
                'SourceSpace', 5124, 'TimeWindow', [250 400], ...
                'ResampleHz', 100, 'RegParam', 0.05);
            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;

            withEstimate = cell(1, numel(files));
            for k = 1:numel(files)
                loaded = load(files{k}, 'EEG');
                EEG = FieldTripFixtures.quietly(@() SourceEstimate(loaded.EEG, settings));
                withEstimate{k} = fullfile(folder, sprintf('sub%d.mat', k));
                save(withEstimate{k}, 'EEG');
            end

            contrast = struct('mode', 'paired', 'binA', 'Related', 'binB', 'Unrelated');
            opts = settings;
            opts.correctm = 'tfce'; opts.numrandomization = 10; opts.Accelerate = true;

            plain  = FieldTripFixtures.quietly(@() SourceClusterStats(files, contrast, opts));
            cached = FieldTripFixtures.quietly(@() SourceClusterStats(withEstimate, contrast, opts));

            testCase.verifyEqual(plain.provenance.reusedEstimates, 0, ...
                'The unmodified datasets carry no estimate, so nothing can be reused.');
            testCase.verifyGreaterThan(cached.provenance.reusedEstimates, 0, ...
                'The stored estimates were not reused, so the keys did not match.');
            testCase.verifyEqual(cached.stat.stat, plain.stat.stat, ...
                'A reused estimate changed the observed statistic.');
        end

        function aChangedSettingRefusesTheStoredEstimate(testCase)
            files = testCase.comparableSubjects();
            testCase.assumeNotEmpty(files, 'No two comparable subject averages available.');

            settings = struct('Method', 'mne', 'Orientation', 'normal', ...
                'SourceSpace', 5124, 'TimeWindow', [250 400], ...
                'ResampleHz', 100, 'RegParam', 0.05);
            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture()).Folder;
            stored = cell(1, numel(files));
            for k = 1:numel(files)
                loaded = load(files{k}, 'EEG');
                EEG = FieldTripFixtures.quietly(@() SourceEstimate(loaded.EEG, settings));
                stored{k} = fullfile(folder, sprintf('sub%d.mat', k));
                save(stored{k}, 'EEG');
            end

            contrast = struct('mode', 'paired', 'binA', 'Related', 'binB', 'Unrelated');
            opts = settings;
            opts.correctm = 'tfce'; opts.numrandomization = 10; opts.Accelerate = true;
            opts.RegParam = 0.20;    % the estimates were made at 0.05

            summary = FieldTripFixtures.quietly(@() SourceClusterStats(stored, contrast, opts));

            testCase.verifyEqual(summary.provenance.reusedEstimates, 0, ...
                'An estimate made at a different regularisation was reused.');
        end
    end

    methods (Access = private)
        function avg = subjectAverage(testCase, seed)
        %SUBJECTAVERAGE  Forty epochs, -200 to 500 ms at 100 Hz, in two bins:
        %   correlated noise, plus a response after 100 ms in bin A.
            rng(seed);
            EEG = makeTestEEG('nbchan', numel(testCase.Labels), 'trials', 40, ...
                'srate', 100, 'epochMs', [-200 500], 'labels', testCase.Labels);
            nChan = numel(testCase.Labels);
            mixing = eye(nChan) + 0.3 * randn(nChan);
            noise = reshape(mixing * reshape(randn(nChan, EEG.pnts * 40), nChan, []), ...
                nChan, EEG.pnts, 40);
            pattern = linspace(-1, 1, nChan)';
            response = pattern * (EEG.times > 100 & EEG.times < 300) * 3;
            EEG.data = noise;
            EEG.data(:, :, 1:20) = EEG.data(:, :, 1:20) + response;
            EEG.bindesc(1) = struct('index', 1, 'label', 'A', 'trials', 1:20, 'combo', []);
            EEG.bindesc(2) = struct('index', 2, 'label', 'B', 'trials', 21:40, 'combo', []);
            avg = Average(EEG);
            avg.File = sprintf('subject%d.set', seed);
        end

        function opts = estimateOpts(~, noise, varargin)
            opts = struct('Method', 'mne', 'Orientation', 'normal', 'SourceSpace', 5124, ...
                'TimeWindow', [], 'ResampleHz', [], 'RegParam', 0.05, ...
                'NoiseCovariance', noise, 'SNR', 3);
            for k = 1:2:numel(varargin)
                opts.(varargin{k}) = varargin{k + 1};
            end
        end

        function files = comparableSubjects(testCase)
        %COMPARABLESUBJECTS  Two subject averages FROM THE SAME MONTAGE.
        %   Not simply the first two found: this dataset carries two
        %   parallel analyses per subject, one of them channel-reduced, and
        %   mixing them makes the shared channel set small enough that no
        %   stored estimate can match. That is correct behaviour and a
        %   useless fixture, so the pair is chosen by equal channel count.
        %   The study's cache is looked for under ALAKAZAM_DATA, Alakazam's
        %   Data folder and D:\data.
            files = {};
            found = [];
            for c = {getenv('ALAKAZAM_DATA'), fullfile(testCase.Alakazam, 'Data'), 'D:\data'}
                if ~isempty(c{1})
                    found = [found; dir(fullfile(c{1}, 'Cache', 'BCN2025*', '**', 'Average*.mat'))]; %#ok<AGROW>
                end
            end
            counts = [];
            paths = {};
            for i = 1:numel(found)
                p = fullfile(found(i).folder, found(i).name);
                loaded = load(p, 'EEG');
                if ~isfield(loaded.EEG, 'bindesc'), continue; end
                if ~all(ismember({'Related', 'Unrelated'}, {loaded.EEG.bindesc.label}))
                    continue;
                end
                counts(end + 1) = numel(loaded.EEG.chanlocs); %#ok<AGROW>
                paths{end + 1} = p; %#ok<AGROW>
            end
            for n = unique(counts)
                same = paths(counts == n);
                if numel(same) >= 2
                    files = same(1:2);
                    return;
                end
            end
        end
    end
end
