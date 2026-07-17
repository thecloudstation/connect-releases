# CloudStation Connect — releases

Compiled, signed, and notarized builds of the CloudStation Connect Mac app,
plus `appcast.xml`, the [Sparkle](https://sparkle-project.org) update feed the
app polls. Nothing but release artifacts lives here — the source repo is
private.

**Install:** download the latest `CloudStationConnect-x.y.z.zip` from
[Releases](https://github.com/thecloudstation/connect-releases/releases),
unzip, and drag "CloudStation Connect.app" into `/Applications` (no sudo —
the app keeps itself updated from then on).

Updates are EdDSA-signed; the app verifies them against its pinned public key
in addition to Apple notarization.
