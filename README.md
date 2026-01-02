# Readme

## Build cache

CI zapisuje cache builda w GHA z `scope=ci`, a produkcyjny build (`live`) używa
`scope=live` z fallbackiem do `scope=ci`. Dzięki temu wspólne warstwy (np. base)
mogą być współdzielone między jobami.
