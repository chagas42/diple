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

## O que existe

**Na notch.** Em repouso o painel tem exatamente o tamanho do recorte e some.
Com pendência abre duas asas na altura da barra de menu, com um olho que
acompanha o ponteiro e o número. No hover expande, com filete côncavo nos
cantos de cima — a emenda com o bezel se esconde na forma, porque num LCD o
preto nunca iguala o recorte físico. Sem recorte, vira pílula flutuante, e o
item da barra de menu só aparece nesse caso.

Quatro abas no painel: a fila, o time com avatares para marcar quem você
acompanha, o rank de reviews dos últimos três meses e o grid de dias em que
você revisou.

**Na janela.** Três colunas. O detalhe traz a conversa com o trecho de código
do `diffHunk`, a visão geral e o review da IA. Dá para responder e resolver
thread sem sair dali.

**Nos avisos.** Som por tipo, agrupados por PR, com resposta inline no banner.

## Review pela sua própria sessão

O Diple não tem IA e não tem servidor. Ele roda o `claude` da sua máquina,
com a sua conta e as suas skills — então o review conhece o `CLAUDE.md` do
repositório e sai na sua voz, e o código não transita por infra de terceiro.

Cada review roda num worktree descartável em `~/.diple/worktrees`, criado de
`refs/pull/N/head`, que existe mesmo quando o PR vem de fork. Seu checkout
não é tocado.

A garantia de que nada é publicado é estrutural, não promessa: a sessão nasce
com `--allowed-tools` só de leitura e `git` de consulta, e `--disallowed-tools`
barrando `Write`, `Edit`, `gh`, `push`, `commit`, `curl` e `WebFetch`. A IA
não escolhe não publicar — ela não tem a ferramenta.

O mapa do PR separa o que é conta do que é julgamento: os módulos alterados
saem do diff sem gastar token; só o que *sente* a mudança e o que você
precisa conhecer pra julgar vão para o modelo.

## Fica para depois

OAuth device flow no lugar do token do `gh`, e SQLite quando existir
histórico de eventos — hoje o estado é um instantâneo por PR aberto,
reescrito inteiro a cada ciclo, e JSON resolve sem adicionar dependência.
