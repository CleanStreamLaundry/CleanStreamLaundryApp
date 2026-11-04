# Native Password Action Labels

October 1, existing iPhone17Pro / iOS26.2 simulator; Clean Stream Debug only.
Existing bounded build wrapper exits0 (4b48d6), ten protected inputs unchanged.
Installed reviewed source hashes match independent QA (6aa1dd); no new packages,
native configuration, signing, cloud deployment, billing or Gundex action.

Before: startup snapshot9 exposed e20 as button with no label. After installation:
snapshot10 screenHash156p9mr exposes `e20|tap|button|Show password||`.
Tapping that observed target yields snapshot11/12, hash18skzqn:
`e20|tap|button|Hide password||`. Tapping again yields snapshot13/hash156p9mr,
restoring Show password. Email and password values remain empty throughout.
No sign-in, account creation, recovery email, permissions or money action.
App PID27718 was stopped successfully; no recorder or build process remains.

Independent widget scope:43 retained and4 new cases, analysis clean; see
`.campaign-work/website-qa/startup-transition/PASSWORD-ACCESSIBILITY.md`.
Those cover sign-up/reset semantics as well. Native bridge observation covers
Login only, not spoken VoiceOver output, full accessibility or Android devices.
