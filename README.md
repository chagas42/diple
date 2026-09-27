# Diple ⟩

Fila de pull requests na barra de menu do macOS. Mostra o que de fato espera
por você e avisa com um som diferente por tipo de evento.

O nome vem da *diple* (διπλῆ), a marca `⟩` que os filólogos de Alexandria
punham na margem do manuscrito para dizer "olha esta linha aqui" — a marca
de revisão mais antiga que existe, e ancestral das nossas aspas.

## Rodar

```sh
make run          # compila, monta o .app, assina ad-hoc e abre
make app          # só monta o bundle
./.build/release/Diple --probe   # inspeciona a camada de dados no terminal
```

Sem Xcode e sem conta Apple paga: `make app` monta o bundle na mão e assina
ad-hoc. Requer `gh` autenticado — o token é emprestado de `gh auth token`.

## Como funciona

Uma única query GraphQL cobre as três filas (seus PRs, os que pediram sua
review, os que você acompanha) e custa **1 ponto** dos 5000/hora. O polling
de 60 s gasta 60 pontos/hora.

Duas coisas que os dados reais ensinaram e que o código depende:

**Comentário humano vive em dois lugares.** `comments` devolve só a conversa
do PR; a resposta que importa costuma ser inline no código, e essa vive em
`reviewThreads`. O app lê os dois e pega o mais recente.

**Bot é a maioria.** Em quase todo PR o último comentário é `coderabbitai` ou
`github-actions`. Sem filtrar por `__typename == "Bot"` e por uma lista de
bots que se apresentam como User, todo aviso viraria ruído de CI.

## Som por tipo

| Evento | Som | Interrompe |
| --- | --- | --- |
| Responderam você | Glass | sim |
| Comentaram no seu PR | Pop | sim |
| Pediram sua review | Tink | sim |
| Check falhou | Basso | sim |
| Aprovaram seu PR | — | não |

`Basso` é o som de erro clássico do macOS: o ouvido já sabe o que significa.
Avisos do mesmo PR são agrupados por `threadIdentifier`, então três
comentários seguidos viram um aviso só.

## Estrutura

```
Sources/Diple/
  DipleApp.swift        MenuBarExtra + ponto de entrada
  Probe.swift           CLI de depuração da camada de dados
  GitHub/               token, query, modelos, cliente
  Core/                 eventos, diff de instantâneos, estado da app
  Notificacoes/         notificador com som por tipo
  UI/                   popover
```

Estado local em `~/Library/Application Support/Diple/estado.json`. A primeira
execução nunca notifica — senão a estreia dispararia um banner por PR aberto.

## Escopo desta v1

Entra: barra de menu com contador, popover com a fila, notificação com som
por tipo, clique abre o PR.

Fica para depois: HUD na notch, janela de três colunas, review pela IA com a
sua própria sessão do Claude, mapa de domínios do PR, tela de ajustes,
OAuth device flow no lugar do token do `gh`.
