function! vimpdb#test()
  echo "vimpdb test"
endfunction

function! vimpdb#initialize()
  let current_dir = expand("<sfile>:h")
  python import sys
  python print sys.path
  "exe 'python sys.path.insert(0, r"' . current_dir . '")'
  "python import VimPdb
endfunction
