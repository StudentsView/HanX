#!/usr/bin/env python3
"""Exercise native Windows console input, including real arrow key events."""
import ctypes, json, os, pathlib, subprocess, sys, tempfile, time
from ctypes import wintypes as W
if os.name != 'nt':
    raise SystemExit('This gate requires native Windows console APIs.')
binary = str(pathlib.Path(sys.argv[1]).resolve())
kernel = ctypes.WinDLL('kernel32', use_last_error=True)
class Character(ctypes.Union):
    _fields_ = [('UnicodeChar', W.WCHAR), ('AsciiChar', W.CHAR)]
class KeyEvent(ctypes.Structure):
    _fields_ = [('bKeyDown', W.BOOL), ('wRepeatCount', W.WORD), ('wVirtualKeyCode', W.WORD),
                ('wVirtualScanCode', W.WORD), ('uChar', Character), ('dwControlKeyState', W.DWORD)]
class Event(ctypes.Union):
    _fields_ = [('KeyEvent', KeyEvent), ('padding', W.BYTE * 16)]
class InputRecord(ctypes.Structure):
    _fields_ = [('EventType', W.WORD), ('Event', Event)]
kernel.CreateFileW.argtypes = [W.LPCWSTR, W.DWORD, W.DWORD, ctypes.c_void_p, W.DWORD, W.DWORD, W.HANDLE]
kernel.CreateFileW.restype = W.HANDLE
kernel.AttachConsole.argtypes = [W.DWORD]
kernel.AttachConsole.restype = W.BOOL
kernel.WriteConsoleInputW.argtypes = [W.HANDLE, ctypes.POINTER(InputRecord), W.DWORD, ctypes.POINTER(W.DWORD)]
kernel.WriteConsoleInputW.restype = W.BOOL
kernel.CloseHandle.argtypes = [W.HANDLE]
kernel.GetConsoleMode.argtypes = [W.HANDLE, ctypes.POINTER(W.DWORD)]
kernel.GetConsoleMode.restype = W.BOOL
assert ctypes.sizeof(InputRecord) == 20, 'Unexpected Windows input record layout'
def key(vk, unit=0):
    record = InputRecord()
    record.EventType = 1
    record.Event.KeyEvent = KeyEvent(True, 1, vk, 0, Character(UnicodeChar=chr(unit)), 0)
    return record
def text_keys(text):
    encoded = text.encode('utf-16-le')
    return [key(0xE7, int.from_bytes(encoded[i:i+2], 'little')) for i in range(0,len(encoded),2)]
def console(words, records, expected=0):
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    process = subprocess.Popen([binary, '--convert', *words], creationflags=subprocess.CREATE_NEW_CONSOLE,
                               startupinfo=startup)
    handle = None
    kernel.FreeConsole()
    try:
        deadline = time.monotonic() + 10
        while not kernel.AttachConsole(process.pid):
            assert process.poll() is None, 'Native console exited before receiving input'
            if time.monotonic() >= deadline: raise ctypes.WinError(ctypes.get_last_error())
            time.sleep(.05)
        handle = kernel.CreateFileW('CONIN$', 0xC0000000, 3, None, 3, 0, None)
        assert handle not in (None, ctypes.c_void_p(-1).value), ctypes.WinError(ctypes.get_last_error())
        batch = (InputRecord * len(records))(*records)
        count = W.DWORD()
        assert kernel.WriteConsoleInputW(handle, batch, len(batch), ctypes.byref(count)), ctypes.WinError(ctypes.get_last_error())
        assert count.value == len(records)
        assert process.wait(timeout=60) == expected
        mode = W.DWORD()
        assert kernel.GetConsoleMode(handle, ctypes.byref(mode)), ctypes.WinError(ctypes.get_last_error())
        assert mode.value & 7 == 7, 'Console line, echo or Ctrl-C mode was not restored'
    finally:
        if handle: kernel.CloseHandle(handle)
        if process.poll() is None: process.kill(); process.wait()
        kernel.FreeConsole()
        kernel.AttachConsole(0xFFFFFFFF)
with tempfile.TemporaryDirectory(prefix='HanX console 한글 ') as temp:
    root = pathlib.Path(temp)
    source = root / '원본 문서.hwp'
    created = subprocess.run([binary,'create','--spec','-','--output',str(source)], input=json.dumps({'kind':'document','text':'Console Unicode path'}),
                             capture_output=True,encoding='utf-8',check=True)
    # Explorer-style exterior quoting preserves every Windows backslash.
    console(['"' + str(source) + '"'], [key(0x28), key(0x0D)])
    assert source.with_suffix('.hwpx').is_file(), 'Down arrow did not select HWPX'
    # A complete dropped Unicode path is read from KEY_EVENT UnicodeChar units.
    console([], text_keys('"' + str(source) + '"') + [key(0x0D), key(0x26), key(0x0D)])
    assert source.with_suffix('.xml').is_file(), 'Up arrow did not wrap to XML'
    console([str(source)], [key(0x1B)], expected=130)
    piped = subprocess.run([binary,'--convert',str(source)], input='1\n',capture_output=True,encoding='utf-8')
    assert piped.returncode != 0 and '터미널' in piped.stdout, piped.stdout
print('Windows real console arrows, dropped Unicode paths, cancellation and non-console guard passed.')
