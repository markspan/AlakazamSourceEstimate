# Source Estimate for Alakazam

A plugin for [Alakazam](https://github.com/markspan/Alakazam): every bin of an averaged dataset inverted onto a template cortical surface, by dSPM or sLORETA, and the estimate stored on the node, so that the source cluster test and the 3D brain read it rather than computing it again.

It was part of Alakazam until it became a plugin of its own, so that it can be
installed, upgraded and documented on its own.

## Manual

The manual is on this repository's pages:
<https://markspan.github.io/AlakazamSourceEstimate/>.

## Installing

In Alakazam, **Install plugins** on the Alakazam tab lists this repository:
select it and press **Install**. It installs the latest release. A zip from
the [releases](https://github.com/markspan/AlakazamSourceEstimate/releases), or one built with
`build`, installs the same way through **From a link**, and so does the link
to this repository. The tool appears on the Tools tab, as it did before.

It needs an Alakazam that no longer carries `SourceEstimate` itself (newer than
V0.4.5.2). Workspaces and templates made with the built-in tool open and
recalculate as before once the plugin is installed; Alakazam offers to
install it when one needs it.

## Building and testing

```matlab
build()                                    % dist/SourceEstimate-<version>.zip
runtests('tests')                          % the tool's tests and the install
```

The tests need Alakazam's source: the folder in `ALAKAZAM_ROOT`, or the
Alakazam repository beside this one.

The tests need FieldTrip, and skip without it; they never download it.

## Licence

GPL-3.0, as Alakazam.
