"""Startet den Minecraft-Server mit den Datenpaketen, schickt Testbefehle und wertet das Log aus.
Mit Carpet gibt es einen Test-Spieler (Bot), damit auch alles geprüft wird, was einen Spieler braucht."""
import subprocess, sys, time, os, re

BOT = os.environ.get('BOT') == '1'
jar = sys.argv[1]
log = open('log.txt', 'w')
p = subprocess.Popen(['java', '-Xmx3G', '-jar', jar, 'nogui'], stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT, text=True)

def text():
    return open('log.txt', encoding='utf-8', errors='replace').read()

def wait_for(pattern, timeout):
    t = time.time()
    while time.time() - t < timeout:
        if re.search(pattern, text()):
            return True
        if p.poll() is not None:
            return False
        time.sleep(1)
    return False

def send(cmd, pause=1.5):
    p.stdin.write(cmd + '\n'); p.stdin.flush(); time.sleep(pause)

started = wait_for(r'Done \(', 420)
if started:
    send('say >>> START')
    send('datapack list enabled')
    send('gamerule send_command_feedback')
    send('say >>> Loot-Funktionen allgemein')
    send('loot spawn 0 100 0 loot test:lit')
    send('execute positioned 0 100 0 run data get entity @e[type=item,limit=1,sort=nearest] Item')
    send('kill @e[type=item]')
    send('function test:daten')
    if BOT:
        send('player Testbot spawn', 5)
        send('gamemode survival Testbot')
        send('say >>> Name eintragen')
        send('execute as Testbot at Testbot run function spieler:db/eintragen')
        send('data get storage spieler:db p')
        send('execute as Testbot at Testbot run data get entity @e[type=item,distance=..3,limit=1] Item')
        send('data get entity Testbot Inventory')
        send('say >>> Menue ueber trigger')
        for n in (1, 2, 3):
            send(f'execute as Testbot run trigger menue set {n}', 2)
            send('function test:dlg with storage spieler:ui')
        send('data get storage spieler:ui dlg')
        send('say >>> Taste G')
        send('dialog show Testbot spieler:menue')
        send('say >>> AFK')
        send('execute as Testbot run trigger afk', 2)
        send('team list afk')
        send('say >>> Komfort')
        for t in ('sethome', 'home', 'spawn', 'zurueck', 'hilfe'):
            send(f'execute as Testbot run trigger {t}', 2)
        send('say >>> Nach allen Tests: Inventar und Items')
        send('data get entity Testbot Inventory')
        send('execute as Testbot at Testbot run data get entity @e[type=item,distance=..5,limit=1] Item')
        send('player Testbot kill', 3)
    else:
        send('say >>> Menues ohne Spieler')
        for f in ('bestenliste', 'meine_werte', 'haupt'):
            send(f'function spieler:menue/{f}')
            send('function test:dlg with storage spieler:ui')
        send('data get storage spieler:ui dlg')
    send('say >>> Entfernen und neu laden')
    send('function spieler:entfernen')
    send('reload', 6)
    send('say >>> ENDE')
    send('stop', 1)
try:
    p.wait(90)
except Exception:
    p.kill()

out = text()
print('================ Log ================')
print(out)
print('================ Auffälligkeiten ================')
bad = []
for i, line in enumerate(out.splitlines(), 1):
    if line.startswith('WARNING: ') or 'OFFLINE/INSECURE' in line or 'online-mode' in line or 'authenticate usernames' in line or 'hackers to connect' in line:
        continue
    if re.search(r"ERROR|WARN|Failed|failed|Unknown|Couldn't|Exception|Expected|Invalid|Incorrect|Whilst|No player|No entity|nicht angezeigt", line):
        print(f'{i}: {line}'); bad.append(line)
print('================ Ende ================')
if not started:
    print('SERVER IST NICHT GESTARTET'); sys.exit(1)
