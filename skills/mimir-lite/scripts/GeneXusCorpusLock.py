"""Exclusive or shared, non-blocking coordination on an existing corpus directory.

Use ``with corpus_lock(corpus_root):`` to change or rebuild from the corpus, and
``with corpus_lock(corpus_root, shared=True):`` to read it: shared holders in
different processes coexist, and any shared holder excludes an exclusive one
(and the reverse). PowerShell participants take only the exclusive lock.
Both kinds lock the same byte, so a process holds at most one kind; a second
corpus lock in the same process is rejected whatever its kind.
The persistent lock file is never
removed or truncated. All participants must use this byte-range protocol;
this primitive alone does not protect a corpus or validate its identity.
Overlapping ownership in this process is rejected before opening a lock file.
A child forked during acquisition is rejected and drops anything it took. If
that child takes the byte lock first, the parent fails with the normal
non-blocking contention error. Such a child and its descendants stay rejected
with a message that says to use a new process.
"""
import contextlib
import os
import threading
from pathlib import Path

_guard = threading.Lock()
_fork = threading.local()
_owned = False
_stream = None
_poisoned = False
_OWNED = 'Corpus lock already owned by this process'
_BUSY = 'Corpus lock busy in this process (acquisition, release, or fork in progress)'
_FORKED = 'Corpus lock unavailable in a process forked during lock acquisition; use a new process'


def _before_fork():
    _fork.reserved = _guard.acquire(False)


def _after_parent():
    if _fork.reserved:
        _guard.release()


def _after_child():
    global _guard, _owned, _stream, _poisoned
    # Only a stable snapshot permits closing inherited descriptors safely.
    _poisoned = _poisoned or not _fork.reserved
    if not _poisoned and _stream is not None:
        _stream.close()
    if not _poisoned: _stream = None
    _owned = False
    _guard = threading.Lock()


_LOCKFILE_FAIL_IMMEDIATELY = 0x1


def _lock_shared_windows(fd):
    """Take a shared, non-blocking lock on byte 0 (LockFileEx without LOCKFILE_EXCLUSIVE_LOCK).

    It conflicts with the exclusive LockFile lock that msvcrt.locking and
    PowerShell's FileStream.Lock take on the same byte, and is released by
    msvcrt.locking(LK_UNLCK), which unlocks the same range.
    """
    import ctypes
    import msvcrt
    from ctypes import wintypes

    class _Overlapped(ctypes.Structure):
        _fields_ = [('Internal', ctypes.c_void_p), ('InternalHigh', ctypes.c_void_p),
                    ('Offset', wintypes.DWORD), ('OffsetHigh', wintypes.DWORD),
                    ('hEvent', wintypes.HANDLE)]

    lock_file_ex = ctypes.WinDLL('kernel32', use_last_error=True).LockFileEx
    lock_file_ex.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD,
                             wintypes.DWORD, ctypes.POINTER(_Overlapped)]
    lock_file_ex.restype = wintypes.BOOL
    overlapped = _Overlapped()  # Offset 0, length 1: the same byte as the exclusive lock
    if not lock_file_ex(msvcrt.get_osfhandle(fd), _LOCKFILE_FAIL_IMMEDIATELY, 0, 1, 0,
                        ctypes.byref(overlapped)):
        raise ctypes.WinError(ctypes.get_last_error())


if hasattr(os, 'register_at_fork'):
    os.register_at_fork(before=_before_fork, after_in_parent=_after_parent,
                        after_in_child=_after_child)


@contextlib.contextmanager
def corpus_lock(corpus_root, *, shared=False):
    global _owned, _stream
    root = Path(corpus_root).resolve(strict=True)
    if not root.is_dir():
        raise NotADirectoryError(str(root))
    path = root / '.mimir-sync.lock'
    owner_pid = os.getpid()
    stream = None
    locked = False
    reserved = False
    try:
        # Release the acquired object: a child forked meanwhile replaces _guard.
        if not (guard := _guard).acquire(False):
            raise RuntimeError(_BUSY)
        try:
            if _poisoned:
                raise RuntimeError(_FORKED)
            if _owned:
                raise RuntimeError(_OWNED)
            _owned = True
            reserved = True
            fd = os.open(str(path), os.O_RDWR | os.O_CREAT, 0o666)
            try:
                stream = os.fdopen(fd, 'r+b', buffering=0)
            except BaseException:
                os.close(fd)
                raise
            if os.getpid() != owner_pid:  # resumed in a child forked mid-acquisition
                stream.close()
                raise RuntimeError(_FORKED)
            _stream = stream
            if os.name == 'nt':
                import msvcrt
                stream.seek(0)
                if shared:
                    _lock_shared_windows(stream.fileno())
                else:
                    msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                try:
                    import fcntl
                    fcntl.lockf(stream.fileno(), (fcntl.LOCK_SH if shared else fcntl.LOCK_EX) | fcntl.LOCK_NB, 1, 0)
                    locked = True
                finally:
                    if os.getpid() != owner_pid:  # forked by this thread inside the import or lockf
                        _stream = None
                        try:
                            if locked:  # record locks are per process: this drops only the child's
                                fcntl.lockf(stream.fileno(), fcntl.LOCK_UN, 1, 0)
                        finally:
                            stream.close()
                        raise RuntimeError(_FORKED)
            locked = True
        finally:
            guard.release()
        if os.getpid() != owner_pid:  # forked by this thread after the checks, before the release
            _stream = None
            stream.close()  # never unlock here: record locks are per process and this one holds none
            raise RuntimeError(_FORKED)
        yield
    finally:
        # An inherited context owns no child state and must not close its stream.
        if os.getpid() == owner_pid and reserved:
            with _guard:
                try:
                    if stream is not None:
                        try:
                            if locked:
                                if os.name == 'nt':
                                    stream.seek(0)
                                    msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
                                else:
                                    fcntl.lockf(stream.fileno(), fcntl.LOCK_UN, 1, 0)
                        finally:
                            stream.close()
                finally:
                    _stream = None
                    _owned = False
