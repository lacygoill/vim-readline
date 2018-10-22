" syntax {{{1

syn region readlineBackticks matchgroup=Comment start=/`/ end=/`/ oneline concealends containedin=readlineComment

" replace noisy markers, used in folds, with ❭ and ❬
exe 'syn match readlineFoldMarkers  /\s*{'.'{{\d*\s*\ze\n/  conceal cchar=❭  containedin=readlineComment'
exe 'syn match readlineFoldMarkers  /\s*}'.'}}\d*\s*\ze\n/  conceal cchar=❬  containedin=readlineComment'

" colors {{{1

hi link  readlineBackticks  Backticks

