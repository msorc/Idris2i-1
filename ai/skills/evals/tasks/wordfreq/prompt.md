I need a small command-line tool in Idris 2 called `wordfreq`.

`wordfreq FILE` prints the 10 most frequent words of the file, one per line as
`<count> <word>`, most frequent first; words with the same count go in alphabetical
order. A word is a maximal run of ASCII letters; words are compared without regard to
case and printed in lower case. If the file has fewer than 10 different words, print
them all.

With no argument, or more than one: print `usage: wordfreq FILE` on standard error and
exit with status 2. If the file cannot be read: print a message on standard error and
exit with status 1.

Make it a package: `wordfreq.ipkg` in the current directory, sources under `src/`, so
that `idris2 --build wordfreq.ipkg` produces `build/exec/wordfreq`.
