#!/usr/bin/env python3
"""Enable IBM Bob in Orca settings. Safe to re-run. Run only while Orca is NOT running."""
import json, os, sys, shutil, datetime, subprocess

DP = os.path.expanduser('~/Library/Application Support/orca/profiles/local-default/orca-data.json')

def orca_running():
    r = subprocess.run(['pgrep','-f','/Applications/Orca'], capture_output=True, text=True)
    return bool(r.stdout.strip())

def main():
    if orca_running() and '--force' not in sys.argv:
        print('REFUSING: Orca is running; it would overwrite settings on quit.')
        print('Quit Orca completely, then re-run this script.')
        return 1
    if not os.path.exists(DP):
        print('not found:', DP); return 1
    data = json.load(open(DP))
    s = data.setdefault('settings', {})
    before = {'disabledTuiAgents': list(s.get('disabledTuiAgents') or []),
              'bobDefaultDisabledMigrated': s.get('bobDefaultDisabledMigrated')}
    bk = DP + '.bak.enable-bob.' + datetime.datetime.now().strftime('%Y%m%d%H%M%S')
    shutil.copy2(DP, bk)

    # 1) make sure bob is not in the disabled list
    disabled = [a for a in (s.get('disabledTuiAgents') or []) if a != 'bob']
    s['disabledTuiAgents'] = disabled
    # 2) mark the one-shot opt-out migration as done so it does not re-add 'bob'
    s['bobDefaultDisabledMigrated'] = True
    # 3) status hooks power Bob's working/done/idle state
    s['agentStatusHooksEnabled'] = True

    tmp = DP + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, DP)
    print('backup   :', bk)
    print('before   :', before)
    print('after    : disabledTuiAgents=%s bobDefaultDisabledMigrated=%s agentStatusHooksEnabled=%s'
          % (s['disabledTuiAgents'], s['bobDefaultDisabledMigrated'], s['agentStatusHooksEnabled']))
    print('OK: Bob enabled.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
