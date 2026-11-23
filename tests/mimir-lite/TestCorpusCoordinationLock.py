import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / 'skills' / 'mimir-lite' / 'scripts'
sys.path.insert(0, str(SCRIPTS))

# The parent can isolate fixtures on a selected filesystem without changing TEMP.
TEST_ROOT = os.environ.get('MIMIR_LOCK_TEST_ROOT')
# The fork probes fork a multi-threaded process on purpose; Python 3.12+ warns about it on stderr.
FORK_PROBE = [sys.executable, '-B', '-W', 'ignore:This process:DeprecationWarning']


class CorpusLockTests(unittest.TestCase):
    def setUp(self):
        if TEST_ROOT:
            Path(TEST_ROOT).mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=TEST_ROOT)
        self.corpus = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def child(self, runtime, action, shared=False):
        if runtime == 'python':
            code = ("import sys; sys.path.insert(0, sys.argv[1]); "
                    "from GeneXusCorpusLock import corpus_lock; "
                    + ("c=corpus_lock(sys.argv[2], shared=True); " if shared else "c=corpus_lock(sys.argv[2]); ")
                    + "c.__enter__(); "
                    + ("print('held',flush=True); sys.stdin.readline(); c.__exit__(None,None,None)" if action == 'hold'
                       else "c.__exit__(None,None,None); print('acquired')"))
            return [sys.executable, '-B', '-c', code, str(SCRIPTS), str(self.corpus)]
        script = ("$ErrorActionPreference = 'Stop'; . $args[0]; $lock = Enter-GeneXusCorpusLock -CorpusRoot $args[1]; "
                  + ("[Console]::WriteLine('held'); [Console]::ReadLine() | Out-Null; " if action == 'hold' else '')
                  + "Exit-GeneXusCorpusLock $lock; " + ("'acquired'" if action != 'hold' else ''))
        # -Command consumes trailing arguments inconsistently; pass literal paths via environment.
        script = script.replace('$args[0]', '$env:MIMIR_TEST_SUPPORT').replace('$args[1]', '$env:MIMIR_TEST_CORPUS')
        return ['pwsh', '-NoProfile', '-NonInteractive', '-Command', script]

    def env(self):
        env = os.environ.copy()
        env.update(MIMIR_TEST_SUPPORT=str(SCRIPTS / 'GeneXusCorpusLockSupport.ps1'), MIMIR_TEST_CORPUS=str(self.corpus))
        return env

    def run_child(self, runtime, shared=False):
        return subprocess.run(self.child(runtime, 'try', shared), env=self.env(), capture_output=True, text=True, timeout=10)

    def start_holder(self, runtime, shared=False):
        proc = subprocess.Popen(self.child(runtime, 'hold', shared), env=self.env(), stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        def stop():
            if proc.poll() is None:
                proc.kill()
                proc.communicate(timeout=10)
        self.addCleanup(stop)
        line = proc.stdout.readline().strip()
        self.assertEqual('held', line, proc.stderr.read() if proc.poll() is not None else '')
        return proc

    def assert_acquired(self, result):
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual('', result.stderr)
        self.assertEqual('acquired', result.stdout.strip())

    def assert_rejected(self, result):
        self.assertNotEqual(0, result.returncode, result.stdout)
        self.assertEqual('', result.stdout)
        self.assertTrue(result.stderr)

    def test_shared_holders_coexist_and_exclude_exclusive_contenders(self):
        first = self.start_holder('python', shared=True)
        second = self.start_holder('python', shared=True)
        self.assert_acquired(self.run_child('python', shared=True))
        self.assert_rejected(self.run_child('python'))
        self.assert_rejected(self.run_child('powershell'))
        first.communicate(input='\n', timeout=10)
        self.assert_rejected(self.run_child('python'))  # the second reader still holds it
        second.communicate(input='\n', timeout=10)
        self.assert_acquired(self.run_child('python'))
        self.assert_acquired(self.run_child('powershell'))

    def test_exclusive_holder_rejects_a_shared_contender(self):
        for holder in ('python', 'powershell'):
            with self.subTest(holder=holder):
                proc = self.start_holder(holder)
                self.assert_rejected(self.run_child('python', shared=True))
                proc.communicate(input='\n', timeout=10)
                self.assert_acquired(self.run_child('python', shared=True))

    def test_python_shared_lock_is_still_one_per_process(self):
        from GeneXusCorpusLock import corpus_lock
        with corpus_lock(self.corpus, shared=True):
            with self.assertRaisesRegex(RuntimeError, 'already owned'):
                with corpus_lock(self.corpus, shared=True):
                    pass
        with corpus_lock(self.corpus):
            pass

    def test_interoperability_and_killed_holder(self):
        for holder, contender in [('python', 'powershell'), ('powershell', 'python')]:
            with self.subTest(holder=holder):
                proc = subprocess.Popen(self.child(holder, 'hold'), env=self.env(), stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                try:
                    self.assertEqual('held', proc.stdout.readline().strip(), proc.stderr.read() if proc.poll() is not None else '')
                    path = self.corpus / '.mimir-sync.lock'
                    self.assertTrue(path.exists())
                    before = path.stat()
                    result = self.run_child(contender)
                    self.assertNotEqual(0, result.returncode, result.stdout)
                    self.assertEqual('', result.stdout)
                    self.assertTrue(result.stderr)
                    proc.kill()
                    proc.communicate(timeout=10)
                    result = self.run_child(contender)
                    self.assertEqual(0, result.returncode, result.stderr)
                    self.assertEqual('', result.stderr)
                    self.assertEqual('acquired', result.stdout.strip())
                    after = path.stat()
                    self.assertEqual((before.st_dev, before.st_ino), (after.st_dev, after.st_ino))
                finally:
                    if proc.poll() is None:
                        proc.kill()
                    proc.communicate(timeout=10)

    def test_normal_release_both_runtimes_preserves_file(self):
        path = self.corpus / '.mimir-sync.lock'
        path.write_bytes(b'persist')
        for runtime in ('python', 'powershell'):
            result = self.run_child(runtime)
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual('acquired', result.stdout.strip())
            self.assertEqual('', result.stderr)
            self.assertEqual(b'persist', path.read_bytes())

    def test_python_normal_exception_nested_and_missing(self):
        from GeneXusCorpusLock import corpus_lock
        path = self.corpus / '.mimir-sync.lock'
        path.write_bytes(b'persist')
        with self.assertRaisesRegex(RuntimeError, 'sentinel'):
            with corpus_lock(self.corpus):
                with self.assertRaises(Exception):
                    with corpus_lock(self.corpus):
                        pass
                raise RuntimeError('sentinel')
        with corpus_lock(self.corpus):
            pass
        self.assertEqual(b'persist', path.read_bytes())
        missing = self.corpus / 'missing'
        with self.assertRaises(Exception):
            with corpus_lock(missing):
                pass
        self.assertFalse(missing.exists())

    @unittest.skipUnless(os.name == 'posix', 'POSIX hard links and record locks')
    def test_python_hardlinked_lock_does_not_release_outer(self):
        from GeneXusCorpusLock import corpus_lock
        other = self.corpus / 'other'
        other.mkdir()
        with corpus_lock(self.corpus):
            os.link(self.corpus / '.mimir-sync.lock', other / '.mimir-sync.lock')
            with self.assertRaisesRegex(RuntimeError, 'already owned'):
                with corpus_lock(other):
                    pass
            result = self.run_child('python')
            self.assertNotEqual(0, result.returncode, result.stdout)
            self.assertEqual('', result.stdout)
            self.assertTrue(result.stderr)
        result = self.run_child('python')
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual('acquired', result.stdout.strip())
        self.assertEqual('', result.stderr)

    @unittest.skipUnless(hasattr(os, 'fork'), 'requires fork')
    def test_paused_open_rejects_contender_and_does_not_block_fork(self):
        # Order-based: the holder stays paused until the script sets resume after its checks.
        code = r"""
import os, sys, threading, time
sys.path.insert(0, sys.argv[1])
from GeneXusCorpusLock import corpus_lock
BUSY, FORKED = 'busy in this process', 'forked during lock acquisition'
entered, resume = threading.Event(), threading.Event()
child, held, contended, (r, w) = [], [], [], os.pipe()
watchdog = threading.Timer(60, resume.set); watchdog.daemon = True; watchdog.start()
def audit(event, args):
    if event == 'open' and str(args[0]).endswith('.mimir-sync.lock'):
        entered.set()
        resume.wait()
        if not child:  # once resumed, the holder forks inside its own open
            child.append(os.fork())
sys.addaudithook(audit)
def attempt():
    try:
        with corpus_lock(sys.argv[2]):
            return True
    except RuntimeError as error:
        if child == [0]:  # the resumed child must stay alive, unlocked, past the release
            os.close(w); os.read(r, 1)
            os._exit(5 if FORKED in str(error) else 6)
        return str(error)
def poisoned_ok():
    message = attempt()
    return message is not True and FORKED in message and 'already owned' not in message
t = threading.Thread(target=lambda: held.append(attempt())); t.start()
assert entered.wait(10)
c = threading.Thread(target=lambda: contended.append(attempt())); c.start()
c.join(10)
prompt = not resume.is_set() and not c.is_alive()
pid = os.fork()
if pid == 0:
    # Both this child and its descendant must retain the uncertain-state poison.
    if not poisoned_ok():
        os._exit(3)
    nested = os.fork()
    if not poisoned_ok():
        os._exit(3)
    os._exit(os.WEXITSTATUS(os.waitpid(nested, 0)[1]) if nested else 0)
deadline, status = time.monotonic() + 10, None  # an upper bound only, never a pass condition
while time.monotonic() < deadline:
    done, code = os.waitpid(pid, os.WNOHANG)
    if done:
        status = code; break
    time.sleep(.01)
unblocked = status is not None and not resume.is_set()
resume.set(); t.join(10); c.join(10)
os.write(w, b'x'); _, resumed = os.waitpid(child[0], 0)
assert prompt and len(contended) == 1 and BUSY in contended[0] and 'already owned' not in contended[0], (prompt, contended)
assert unblocked and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0, (unblocked, status)
assert held == [True] and os.WIFEXITED(resumed) and os.WEXITSTATUS(resumed) == 5, (held, resumed)
print('verified')
"""
        result = subprocess.run(FORK_PROBE + ['-c', code, str(SCRIPTS), str(self.corpus)],
                                capture_output=True, text=True, timeout=120)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual('verified\n', result.stdout); self.assertEqual('', result.stderr)

    def run_same_thread_fork(self, event):
        # Fork from an audit hook on the acquiring thread itself; the child goes first.
        code = r"""
import os, select, sys
sys.path.insert(0, sys.argv[1])
from GeneXusCorpusLock import corpus_lock
EVENT = sys.argv[3]
if EVENT == 'import' and 'fcntl' in sys.modules:
    print('preloaded'); sys.exit(0)
top, child, entered = os.getpid(), [], []
rejected_r, rejected_w = os.pipe()
release_r, release_w = os.pipe()
def audit(event, args):
    if child or event != EVENT or (event == 'import' and args[0] != 'fcntl'):
        return
    child.append(os.fork())
    if child[0]:
        # Resume only after the child was rejected; EOF means it never was.
        os.close(rejected_w)
        select.select([rejected_r], [], [], 5)
sys.addaudithook(audit)
def lock_descriptors():
    if not os.path.isdir('/proc/self/fd'):
        return 0
    return sum(os.path.realpath('/proc/self/fd/' + fd).endswith('.mimir-sync.lock')
               for fd in os.listdir('/proc/self/fd'))
try:
    with corpus_lock(sys.argv[2]):
        if os.getpid() != top:
            os._exit(3)  # a forked child must never enter the body
        entered.append(True)
except BaseException as error:
    if os.getpid() == top:
        raise
    clean = (isinstance(error, RuntimeError) and 'forked during lock acquisition' in str(error)
             and not lock_descriptors())
    os.write(rejected_w, b'r' if clean else b'x')
    os.read(release_r, 1)  # stay alive until the parent has released
    os._exit(0 if clean else 4)
if os.getpid() != top:
    os._exit(5)
os.write(release_w, b'x')
_, status = os.waitpid(child[0], 0)
assert entered and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0, (entered, status)
with corpus_lock(sys.argv[2]):
    pass
print('verified')
"""
        result = subprocess.run(FORK_PROBE + ['-c', code, str(SCRIPTS), str(self.corpus), event],
                                capture_output=True, text=True, timeout=20)
        if result.stdout == 'preloaded\n':
            self.skipTest('fcntl is already imported at interpreter startup')
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual('verified\n', result.stdout)
        self.assertEqual('', result.stderr)

    @unittest.skipUnless(hasattr(os, 'fork'), 'requires fork')
    def test_same_thread_fork_at_lockf_rejects_child_without_lock(self):
        self.run_same_thread_fork('fcntl.lockf')

    @unittest.skipUnless(hasattr(os, 'fork'), 'requires fork')
    def test_same_thread_fork_at_fcntl_import_rejects_child_without_lock(self):
        self.run_same_thread_fork('import')

    @unittest.skipUnless(hasattr(os, 'fork'), 'requires fork')
    def test_same_thread_fork_before_guard_release_rejects_child(self):
        # A line trace forks on the acquiring thread itself (as a signal handler could)
        # after the post-lockf checks, just before the guard is released; the child goes first.
        code = r"""
import linecache, os, select, subprocess, sys
sys.path.insert(0, sys.argv[1])
from GeneXusCorpusLock import corpus_lock
FORKED = 'forked during lock acquisition'
top, child, reports = os.getpid(), [], []
report_r, report_w = os.pipe()
release_r, release_w = os.pipe()
def lock_descriptors():
    if not os.path.isdir('/proc/self/fd'):
        return 0
    return sum(os.path.realpath('/proc/self/fd/' + fd).endswith('.mimir-sync.lock')
               for fd in os.listdir('/proc/self/fd'))
def line(frame, event, arg):
    # Matched by source text so that edits elsewhere in the module keep the target.
    if (event == 'line' and not child
            and linecache.getline(frame.f_code.co_filename, frame.f_lineno).strip() == 'guard.release()'):
        child.append(os.fork())
        if child[0]:
            # Resume only after the child reported; a timeout is recorded, never a pass.
            ready = select.select([report_r], [], [], 10)[0]
            reports.append(os.read(report_r, 64) if ready else b'timeout')
    return line
def calls(frame, event, arg):
    code = frame.f_code
    if code.co_name == 'corpus_lock' and os.path.basename(code.co_filename) == 'GeneXusCorpusLock.py':
        return line
contender = ("import sys; sys.path.insert(0, sys.argv[1]); "
             "from GeneXusCorpusLock import corpus_lock; "
             "c=corpus_lock(sys.argv[2]); c.__enter__(); c.__exit__(None,None,None); print('acquired')")
held = None
sys.settrace(calls)
try:
    with corpus_lock(sys.argv[2]):
        sys.settrace(None)
        if os.getpid() != top:  # a forked child must never enter the body
            os.write(report_w, b'body %d' % lock_descriptors())
            os.read(release_r, 1)
            os._exit(3)
        result = subprocess.run([sys.executable, '-B', '-W', 'ignore:This process:DeprecationWarning', '-c', contender, sys.argv[1], sys.argv[2]],
                                capture_output=True, text=True, timeout=10)
        held = result.returncode != 0 and result.stdout == '' and 'BlockingIOError' in result.stderr
except BaseException as error:
    sys.settrace(None)
    if os.getpid() == top:
        raise
    clean = isinstance(error, RuntimeError) and FORKED in str(error)
    os.write(report_w, (b'rejected %d' % lock_descriptors()) if clean else b'other ' + repr(error).encode()[:50])
    os.read(release_r, 1)  # stay alive until the parent has released
    os._exit(0)
assert child, 'guard.release() was never traced'
os.write(release_w, b'x')
_, status = os.waitpid(child[0], 0)
with corpus_lock(sys.argv[2]):
    pass
assert reports == [b'rejected 0'], reports
assert held and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0, (held, status)
print('verified')
"""
        result = subprocess.run(FORK_PROBE + ['-c', code, str(SCRIPTS), str(self.corpus)],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual('verified\n', result.stdout)
        self.assertEqual('', result.stderr)

    @unittest.skipUnless(hasattr(os, 'fork'), 'requires fork')
    def test_python_fork_child_retries_after_parent_release(self):
        code = r"""
import os, select, sys
sys.path.insert(0, sys.argv[1])
from GeneXusCorpusLock import corpus_lock
read_fd, write_fd = os.pipe()
ready_in, ready_out = os.pipe()
with corpus_lock(sys.argv[2]):
    pid = os.fork()
    if pid == 0:
        os.close(write_fd)
        os.close(ready_in)
        try:
            with corpus_lock(sys.argv[2]):
                os._exit(4)
        except BlockingIOError:
            os.write(ready_out, b'b')
        except Exception:
            os._exit(5)
        os.close(ready_out)
        if not select.select([read_fd], [], [], 5)[0] or os.read(read_fd, 1) != b'x':
            os._exit(2)
        try:
            with corpus_lock(sys.argv[2]):
                print('acquired', flush=True)
        except Exception as exc:
            print(repr(exc), file=sys.stderr, flush=True)
            os._exit(3)
        os._exit(0)
    os.close(ready_out)
    if not select.select([ready_in], [], [], 5)[0] or os.read(ready_in, 1) != b'b':
        sys.exit('forked child did not encounter OS lock contention')
    os.close(ready_in)
os.close(read_fd)
os.write(write_fd, b'x')
os.close(write_fd)
_, status = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(status) if hasattr(os, 'waitstatus_to_exitcode') else status >> 8)
"""
        result = subprocess.run(FORK_PROBE + ['-c', code, str(SCRIPTS), str(self.corpus)],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual('acquired', result.stdout.strip())
        self.assertEqual('', result.stderr)

    @unittest.skipUnless(hasattr(os, 'fork'), 'requires fork')
    def test_fork_inherited_context_exit_keeps_child_lock(self):
        code = r"""
import os, select, subprocess, sys
sys.path.insert(0, sys.argv[1])
from GeneXusCorpusLock import corpus_lock

def receive(fd, expected):
    if not select.select([fd], [], [], 5)[0] or os.read(fd, 1) != expected:
        raise RuntimeError('child synchronization failed: ' + repr(expected))

def probe(blocked):
    code = ("import sys; sys.path.insert(0, sys.argv[1]); "
            "from GeneXusCorpusLock import corpus_lock; "
            "c=corpus_lock(sys.argv[2]); c.__enter__(); c.__exit__(None,None,None); print('acquired')")
    result = subprocess.run([sys.executable, '-B', '-W', 'ignore:This process:DeprecationWarning', '-c', code, sys.argv[1], sys.argv[2]],
                            capture_output=True, text=True, timeout=5)
    if blocked:
        assert result.returncode != 0 and result.stdout == '' and result.stderr, result
    else:
        assert result.returncode == 0 and result.stdout == 'acquired\n' and result.stderr == '', result

parent_read, child_write = os.pipe()
child_read, parent_write = os.pipe()
outer = corpus_lock(sys.argv[2])
outer.__enter__()
pid = os.fork()
if pid == 0:
    os.close(parent_read)
    os.close(parent_write)
    try:
        os.write(child_write, b'f')
        receive(child_read, b'a')
        inner = corpus_lock(sys.argv[2])
        inner.__enter__()
        os.write(child_write, b'h')
        receive(child_read, b'u')
        outer.__exit__(None, None, None)
        os.write(child_write, b'u')
        receive(child_read, b'r')
        inner.__exit__(None, None, None)
        os.write(child_write, b'r')
        os._exit(0)
    except BaseException as exc:
        print(repr(exc), file=sys.stderr, flush=True)
        os._exit(1)
os.close(child_read)
os.close(child_write)
try:
    receive(parent_read, b'f')
    probe(True)  # The parent's lock survives the fork.
    outer.__exit__(None, None, None)
    os.write(parent_write, b'a')
    receive(parent_read, b'h')
    probe(True)
    os.write(parent_write, b'u')
    receive(parent_read, b'u')
    probe(True)  # Exiting the inherited context must not release the child's lock.
    os.write(parent_write, b'r')
    receive(parent_read, b'r')
    probe(False)
    _, status = os.waitpid(pid, 0)
    assert os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0, status
    print('verified')
finally:
    os.close(parent_read)
    os.close(parent_write)
"""
        result = subprocess.run(FORK_PROBE + ['-c', code, str(SCRIPTS), str(self.corpus)],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual('verified', result.stdout.strip())
        self.assertEqual('', result.stderr)

    def test_powershell_runspace_reservation_keeps_outer_lock(self):
        other = self.corpus / 'other'
        other.mkdir()
        script = r"""
$ErrorActionPreference = 'Stop'
. $env:MIMIR_TEST_SUPPORT
$outer = Enter-GeneXusCorpusLock $env:MIMIR_TEST_CORPUS
try {
    $ps = [powershell]::Create()
    try {
        [void]$ps.AddScript({
            $ErrorActionPreference = 'Stop'
            . $env:MIMIR_TEST_SUPPORT
            foreach ($root in @($env:MIMIR_TEST_CORPUS, (Join-Path $env:MIMIR_TEST_CORPUS 'other'))) {
                try {
                    $inner = Enter-GeneXusCorpusLock $root
                    Exit-GeneXusCorpusLock $inner
                    'acquired'
                } catch {
                    if ($_.Exception.Message -ne 'Corpus lock already owned by this process') { throw }
                    'rejected'
                }
            }
        })
        $results = @($ps.Invoke())
        [Console]::WriteLine(($results -join ','))
        [Console]::ReadLine() | Out-Null
    } finally { $ps.Dispose() }
} finally { Exit-GeneXusCorpusLock $outer }
"""
        proc = subprocess.Popen(['pwsh', '-NoProfile', '-NonInteractive', '-Command', script],
                                env=self.env(), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True)
        try:
            line = proc.stdout.readline().strip()
            if not line:
                _, stderr = proc.communicate(timeout=10)
                self.fail('holder exited before reporting runspace results: ' + stderr)
            self.assertEqual('rejected,rejected', line)
            self.assertFalse((other / '.mimir-sync.lock').exists())
            result = self.run_child('python')
            self.assertNotEqual(0, result.returncode)
            self.assertEqual('', result.stdout)
            self.assertTrue(result.stderr)
            proc.stdin.write('\n')
            proc.stdin.flush()
            stdout, stderr = proc.communicate(timeout=10)
            self.assertEqual(0, proc.returncode, stderr)
            self.assertEqual('', stdout)
            self.assertEqual('', stderr)
            result = self.run_child('python')
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual('acquired', result.stdout.strip())
            self.assertEqual('', result.stderr)
        finally:
            if proc.poll() is None:
                proc.kill()
            proc.communicate(timeout=10)

    def test_powershell_nested_and_exception_release(self):
        script = r"""
$ErrorActionPreference = 'Stop'
. $env:MIMIR_TEST_SUPPORT
try { Enter-GeneXusCorpusLock (Join-Path $env:MIMIR_TEST_CORPUS 'missing'); exit 8 } catch { }
if (Test-Path (Join-Path $env:MIMIR_TEST_CORPUS 'missing')) { exit 7 }
try {
    $l = Enter-GeneXusCorpusLock $env:MIMIR_TEST_CORPUS
    try {
        try { $other = Enter-GeneXusCorpusLock $env:MIMIR_TEST_CORPUS; exit 9 } catch { }
        throw 'sentinel'
    } finally { Exit-GeneXusCorpusLock $l }
} catch { if ($_.Exception.Message -ne 'sentinel') { throw } }
$l = Enter-GeneXusCorpusLock $env:MIMIR_TEST_CORPUS
Exit-GeneXusCorpusLock $l
"""
        result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', script], env=self.env(), capture_output=True, text=True, timeout=10)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual('', result.stdout)


if __name__ == '__main__':
    unittest.main()
