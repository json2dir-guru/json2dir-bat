# json2dir-bat

[json2dir](https://github.com/kitsunoff/awesome-json2dir) in pure cmd.exe batch (builtins only): creates the directory tree a JSON document describes, in the current directory.

    json2dir.bat < document.json

Non-ASCII text needs `chcp 65001`; scripts, NUL, non-ASCII `\u` escapes and content starting with whitespace, `=` or `"` are rejected (see the header of `json2dir.bat`).
