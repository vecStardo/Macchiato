# Macchiato

Macchiato is a minimal macOS menu bar utility with one switch: keep the Mac awake, including lid-closed use.

It uses an IOKit `PreventUserIdleSystemSleep` assertion plus macOS' `pmset disablesleep` setting. The app now ships a privileged LaunchDaemon helper, installed through `SMAppService`, so the system-level `pmset` work is approved once instead of prompting on every toggle.

## Helper approval

The first time Macchiato needs lid-closed sleep control, macOS may require the user to approve **Macchiato Helper** in System Settings. After approval, normal on/off toggles communicate with the helper over XPC and should not ask for administrator credentials again.

Apps that register LaunchDaemons with `SMAppService` must be code signed, and production distribution must be notarized. For release builds, set a real Apple Developer Team and notarize the containing app bundle. The XPC connection validates bundle identifiers and, when available, the signing Team ID.

## Recovery

If Macchiato is force-quit or crashes while enabled, restore normal sleep behavior manually:

```sh
sudo pmset -a disablesleep 0
```

## Build

```sh
xcodebuild -project Macchiato.xcodeproj -scheme Macchiato -configuration Debug build
```

The `Macchiato` target depends on `Macchiato Power Helper` and embeds the helper executable plus its launchd plist into:

```text
Macchiato.app/Contents/MacOS/app.macchiato.Macchiato.PowerHelper
Macchiato.app/Contents/Library/LaunchDaemons/app.macchiato.Macchiato.PowerHelper.plist
```

## Verify the assertion

Launch the app, turn on **Keep Mac Awake**, then run:

```sh
pmset -g assertions | grep Macchiato
```

You should see a `PreventUserIdleSystemSleep` assertion named `Macchiato is keeping your Mac awake`.

You can also verify the lid-closed sleep setting:

```sh
pmset -g live | grep SleepDisabled
```

## Local Sleep Logging Test

The repo includes two local scripts for manual acceptance testing:

```sh
scripts/sleep-log-runner.sh --scenario lid-closed-off
scripts/sleep-log-runner.sh --scenario keep-awake-on
scripts/analyze-sleep-log.sh sleep-test-logs/*.csv
```

Suggested flow:

1. Ensure Macchiato is off, start `scripts/sleep-log-runner.sh --scenario lid-closed-off`, close the lid or otherwise trigger the sleep condition, wait 10 minutes, reopen the Mac, then stop the logger with Ctrl+C.
2. Turn on **Keep Mac Awake**, start `scripts/sleep-log-runner.sh --scenario keep-awake-on`, repeat the 10 minute window, reopen the Mac, then stop the logger.
3. Run `scripts/analyze-sleep-log.sh sleep-test-logs/*.csv`.

The analyzer reports sample count, wall time, maximum timestamp gap, whether the Macchiato power assertion was observed, and how many samples saw `SleepDisabled=1`. A large gap means the logger stopped running during the test window, which usually indicates sleep.
