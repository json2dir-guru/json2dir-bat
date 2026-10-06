@goto :main
X	__Y
:main
@echo off
rem json2dir.bat - create the directory tree described by a JSON document (RFC J2D-1).
rem Usage: json2dir.bat < document.json      (pure cmd.exe: builtins only)
rem Line 2 of this file holds the control characters U+0001..U+001F and U+007F (and a lone CR);
rem the script reads them back with SET /P because cmd has no other way to make them.
rem
rem Known limits (the tool fails instead of writing wrong data):
rem  - non-ASCII text needs the UTF-8 code page (chcp 65001 before running);
rem  - \u escapes are supported for ASCII only; NUL is rejected;
rem  - ["script", ...] is rejected: Windows has no execute bit (RFC section 10);
rem  - file content must not start with whitespace, "=" or a quote (SET /P strips them);
rem  - names that Windows cannot hold (\ : * ? " < > | control chars, trailing dot or space,
rem    device names like CON or NUL) are rejected;
rem  - more than 200 blank lines in a row are taken as the end of input.

setlocal DisableDelayedExpansion
if not "%~1"=="" (
  >&2 echo usage: json2dir.bat ^< document.json
  exit /b 2
)

rem ---------- character tables ----------
(set LF=^
%=this line must stay empty=%
)
set "Q=""
rem Printable ASCII from U+0020; the quote and "=" are replaced by "_" (handled separately).
set "PRINT= !_#$%%&'()*+,-./0123456789:;<_>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
rem Characters that Windows does not allow in names.
set "W_<=1"
set "W_>=1"
set "W_:=1"
set "W_|=1"
set "W_?=1"
set "W_*=1"
set "W_\=1"
set "W_/=1"
for %%h in (0 1 2 3 4 5 6 7 8 9 a b c d e f) do set "H_%%h=1"
rem Code page probe: this is one character in UTF-8 (chcp 65001), two in single-byte code pages.
set "U8=Ж"
set "BAD=�"

setlocal EnableDelayedExpansion
set "L1="
set "L2="
<"%~f0" (
  set /p "L1="
  set /p "L2="
)
set "CTRL=!L2:~1,32!"
set "CR=!L2:~33,1!"
set "TAB=!CTRL:~8,1!"
for /l %%i in (0,1,94) do if %%i neq 2 if %%i neq 29 set "P_!PRINT:~%%i,1!=1"
set "P_!CTRL:~31,1!=1"
for /l %%i in (0,1,30) do if %%i neq 9 if %%i neq 12 set "C_!CTRL:~%%i,1!=1"
set "UTF8="
if "!U8:~1!"=="" set "UTF8=1"

rem ---------- read all of standard input ----------
rem SET /P returns up to 1023 bytes, splits at CRLF and drops trailing control characters.
rem Those are JSON whitespace, so the chunks are parsed as one stream.
set /a n=0, empties=0
:read
set "line="
set /p "line="
if defined line (
  set /a n+=1, empties=0
  set "R!n!=!line!"
  goto read
)
set /a empties+=1
if !empties! lss 200 goto read

rem ---------- parse and validate the whole document ----------
set /a ri=0, pos=0, nn=0
set "buf="
set "D0=."
call :skipws
if not defined c call :die "empty input"
if not "!c!"=="{" call :die "the root of the document must be an object"
set /a pos+=1
call :object 0
call :skipws
if defined c call :die "unexpected data after the document"

rem ---------- create the tree ----------
for /l %%i in (1,1,!nn!) do call :make %%i
exit /b 0


rem ======================= reader =======================
rem :peek sets c to the current character, or undefines it at the end of input.
:peek
set "c="
if defined buf set "c=!buf:~%pos%,1!"
if defined c exit /b 0
if !ri! geq !n! exit /b 0
set /a ri+=1, pos=0
set "buf=!R%ri%!"
goto peek

:getc
call :peek
if not defined c call :die "unexpected end of input"
set /a pos+=1
exit /b 0

:skipws
call :peek
if not defined c exit /b 0
set "ws="
if "!c!"==" " set "ws=1"
if "!c!"=="!TAB!" set "ws=1"
if "!c!"=="!LF!" set "ws=1"
if "!c!"=="!CR!" set "ws=1"
if not defined ws exit /b 0
set /a pos+=1
goto skipws


rem ======================= parser =======================
rem Nodes are numbered in document order: T<id> type, N<id> name, P<id> parent,
rem V<id>_1..V<id>_n content chunks.  Node 0 is the target directory.

rem :object <id>  - after "{"
:object
call :skipws
if "!c!"=="}" (
  set /a pos+=1
  exit /b 0
)
:obj_member
call :skipws
if not "!c!"=="!Q!" call :die "expected a member name"
call :string NM
call :checkname
set /a nn+=1
set "N!nn!=!NM_1!"
set "P!nn!=%1"
call :skipws
if not "!c!"==":" call :die "expected ':' after a member name"
set /a pos+=1
call :value !nn!
call :skipws
if "!c!"=="," (
  set /a pos+=1
  goto obj_member
)
if "!c!"=="}" (
  set /a pos+=1
  exit /b 0
)
call :die "expected ',' or '}' in an object"

rem :value <id>
:value
call :skipws
if not defined c call :die "unexpected end of input"
if "!c!"=="{" (
  set "T%1=obj"
  set /a pos+=1
  call :object %1
  exit /b 0
)
if "!c!"=="!Q!" (
  set "T%1=str"
  call :string V%1
  call :checkcontent V%1
  exit /b 0
)
if "!c!"=="[" (
  set /a pos+=1
  call :array %1
  exit /b 0
)
call :die "values must be objects, strings or arrays (numbers, true, false and null are not allowed)"

rem :array <id>  - after "["
:array
call :skipws
if not "!c!"=="!Q!" call :die "an array must be [link, target]"
call :string KIND
call :skipws
if not "!c!"=="," call :die "an array must have exactly two strings"
set /a pos+=1
call :skipws
if not "!c!"=="!Q!" call :die "an array must have exactly two strings"
call :string V%1
set "TQ=!HASQ!!HASCTL!"
call :skipws
if not "!c!"=="]" call :die "an array must have exactly two strings"
set /a pos+=1
if "!KIND_n!!KIND_1!"=="1script" call :die "scripts are not supported: Windows has no execute permission (RFC section 10)"
if not "!KIND_n!!KIND_1!"=="1link" call :die "unknown array kind (expected link)"
if not "!V%1_n!"=="1" call :die "link target too long"
if defined TQ call :die "a link target with quotes or control characters cannot be passed to mklink"
set "T%1=link"
exit /b 0

rem :string <prefix>  - c is the opening quote. Decodes into <prefix>_1..<prefix>_n chunks,
rem split before a "safe" character so that every chunk can be written with SET /P.
:string
set /a pos+=1, k=0, alen=0
set "acc="
set "HASQ="
set "HASCTL="
:str_loop
set "c="
if defined buf set "c=!buf:~%pos%,1!"
if not defined c call :peek
if not defined c call :die "unterminated string"
set /a pos+=1
if "!c!"=="!Q!" goto str_end
if "!c!"=="\" goto str_esc
if "!c!"=="!LF!" call :die "raw control character in a string"
if "!c!"=="!CR!" call :die "raw control character in a string"
if defined C_!c! call :die "raw control character in a string"
if not defined UTF8 if not "!c!"=="=" if not defined P_!c! call :die "non-ASCII text needs the UTF-8 code page: run chcp 65001 first"
if defined UTF8 if "!c!"=="!BAD!" call :die "input is not valid UTF-8 (or contains U+FFFD)"
set "d=!c!"
goto str_add

:str_esc
call :getc
set "d="
if "!c!"=="!Q!" (
  set "d=!Q!"
  set "HASQ=1"
)
if "!c!"=="\" set "d=\"
if "!c!"=="/" set "d=/"
if "!c!"=="b" set "d=!CTRL:~7,1!"
if "!c!"=="f" set "d=!CTRL:~11,1!"
if "!c!"=="n" set "d=!LF!"
if "!c!"=="r" set "d=!CR!"
if "!c!"=="t" set "d=!TAB!"
if "!c!"=="u" goto str_hex
if not defined d call :die "invalid escape in a string"
for %%e in (b f n r t) do if "!c!"=="%%e" set "HASCTL=1"
goto str_add

:str_hex
set "hex="
for %%j in (1 2 3 4) do call :hexdigit
set /a code=0x!hex!
if !code! equ 0 call :die "NUL characters cannot be written by cmd"
if !code! geq 128 call :die "\u escapes are supported for ASCII only"
if !code! lss 32 set "HASCTL=1"
if !code! equ 127 set "HASCTL=1"
set "d="
if !code! equ 10 set "d=!LF!"
if !code! equ 13 set "d=!CR!"
if !code! equ 34 set "d=!Q!"
if !code! equ 34 set "HASQ=1"
if !code! equ 61 set "d=="
if !code! equ 127 set "d=!CTRL:~31,1!"
if !code! lss 32 (set /a x=code-1) else (set /a x=code-32)
if not defined d if !code! lss 32 for %%x in (!x!) do set "d=!CTRL:~%%x,1!"
if not defined d for %%x in (!x!) do set "d=!PRINT:~%%x,1!"
goto str_add

:hexdigit
call :getc
if not defined H_!c! call :die "invalid \u escape"
set "hex=!hex!!c!"
exit /b 0

:str_add
if !alen! geq 2000 call :str_split %1
set "acc=!acc!!d!"
set /a alen+=1
goto str_loop

:str_split
if "!d!"==" " goto split_unsafe
if not defined P_!d! goto split_unsafe
set /a k+=1
set "%1_!k!=!acc!"
set "acc="
set /a alen=0
exit /b 0
:split_unsafe
if !alen! geq 7000 call :die "string too long without a split point"
exit /b 0

:str_end
if defined acc (
  set /a k+=1
  set "%1_!k!=!acc!"
)
if !k! equ 0 (
  set /a k=1
  set "%1_1="
)
set "%1_n=!k!"
exit /b 0

rem :checkname - validates NM_1 (the name just decoded)
:checkname
if not "!NM_n!"=="1" call :die "name too long"
set "nm=!NM_1!"
if not defined nm call :die "empty name"
if "!nm!"=="." call :die "invalid name ."
if "!nm!"==".." call :die "invalid name .."
if defined HASQ call :die "a name cannot contain a quote on Windows"
if defined HASCTL call :die "a name cannot contain control characters on Windows"
if not "!nm:~255!"=="" call :die "name too long"
for /l %%j in (0,1,254) do (
  set "ch=!nm:~%%j,1!"
  if defined ch if defined W_!ch! call :die "a name contains / or a character Windows does not allow"
)
if "!nm:~-1!"=="." call :die "a name cannot end with a dot on Windows"
if "!nm:~-1!"==" " call :die "a name cannot end with a space on Windows"
set "base="
for /f "delims=." %%b in ("x!nm!") do set "base=%%b"
for %%r in (CON PRN AUX NUL COM1 COM2 COM3 COM4 COM5 COM6 COM7 COM8 COM9 LPT1 LPT2 LPT3 LPT4 LPT5 LPT6 LPT7 LPT8 LPT9 CONIN$ CONOUT$) do (
  if /i "!base!"=="x%%r" call :die "a name is a reserved device name on Windows"
)
exit /b 0

rem :checkcontent <prefix> - SET /P drops leading whitespace and chokes on a leading "=" or quote.
:checkcontent
if not defined %1_1 exit /b 0
set "c0=!%1_1:~0,1!"
if "!c0!"==" " goto bad_start
if "!c0!"=="=" goto bad_start
if "!c0!"=="!Q!" goto bad_start
if "!c0!"=="!LF!" goto bad_start
if "!c0!"=="!CR!" goto bad_start
if defined C_!c0! goto bad_start
exit /b 0
:bad_start
call :die "file content starting with whitespace, a control character, '=' or a quote cannot be written by cmd"


rem ======================= writer =======================
rem :make <id> - create node <id>; parents always come before their children.
:make
for %%p in (!P%1!) do set "pd=!D%%p!"
set "pth=!pd!\!N%1!"
set "D%1=!pth!"
set "a="
for %%F in ("!pth!") do set "a=%%~aF"
set "isdir="
set "islink="
if defined a if "!a:~0,1!"=="d" set "isdir=1"
if defined a if "!a:~8,1!"=="l" set "islink=1"
if "!T%1!"=="obj" goto make_dir
if defined isdir if not defined islink call :die "a directory is in the way of a non-directory member"
if defined a call :remove
if "!T%1!"=="link" goto make_link

rem regular file
if not defined V%1_1 (
  type nul > "!pth!"
  goto made_file
)
(
  for /l %%j in (1,1,!V%1_n!) do <nul set /p "=!V%1_%%j!"
) > "!pth!"
rem A leading non-ASCII character may be a space SET /P drops: read the file back and compare.
set "c0=!V%1_1:~0,1!"
if not defined P_!c0! (
  set "chk="
  <"!pth!" set /p "chk="
  if not "!chk:~0,1!"=="!c0!" (
    del /f /q /a "!pth!" >nul 2>nul
    call :die "file content starting with a space-like character cannot be written by cmd"
  )
)
:made_file
if not exist "!pth!" call :die "cannot write a file"
exit /b 0

:make_dir
if defined isdir if not defined islink exit /b 0
if defined a call :remove
md "!pth!" || call :die "cannot create a directory"
exit /b 0

:make_link
set "tg=!V%1_1!"
set "lk="
pushd "!pd!" || call :die "cannot enter a directory"
if defined tg if exist "!tg!\" set "lk=/d"
popd
mklink !lk! "!pth!" "!tg!" >nul || call :die "cannot create a symbolic link"
exit /b 0

rem :remove - remove the existing non-directory (or link) at pth; never follows links.
:remove
if defined isdir (rd "!pth!") else (del /f /q /a "!pth!")
set "a="
for %%F in ("!pth!") do set "a=%%~aF"
if defined a call :die "cannot remove an existing entry"
exit /b 0


rem ======================= errors =======================
rem :die stops the whole script from any CALL depth (an intentional syntax error ends
rem batch processing; the exit code is 255).
:die
>&2 echo json2dir: %~1
call :halt 2>nul
:halt
()
