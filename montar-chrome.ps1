<#
  montar-chrome.ps1

  O "chrome" (faixa de anuncio, header, paineis, rodape, botao flutuante de
  WhatsApp, menu inferior e painel de cookies) esta repetido em todas as
  paginas. Isso e intencional: injetar por fetch quebraria em file:// e
  atrasaria a primeira pintura. Mas repetir na mao erro, e ja errou.

  COMO FUNCIONA
    Cada bloco fica entre um marcador de abertura e um de fechamento, que
    PERMANECEM nas paginas. O script troca so o que esta ENTRE os marcadores,
    entao pode ser rodado quantas vezes for preciso (e idempotente).

  USO
    1. Edite o chrome em index.html, mantendo os marcadores:
         <!--@FAIXA-->    ... <!--@FIMFAIXA-->
         <!--@HEADER-->   ... <!--@FIMHEADER-->
         <!--@PAINEIS-->  ... <!--@FIMPAINEIS-->
         <!--@RODAPE-->   ... <!--@FIMRODAPE-->
         <!--@ZAP-->      ... <!--@FIMZAP-->
         <!--@TABBAR-->   ... <!--@FIMTABBAR-->
         <!--@COOKIES-->  ... <!--@FIMCOOKIES-->
    2. Faca uma copia da pasta (primeira vez) e rode, a partir da raiz do site:
         powershell -File tools\montar-chrome.ps1
       O script funciona na raiz do site ou numa subpasta (ex.: tools).
    3. Confira o relatorio: cada pagina deve ter 7 marcadores de abertura e
       7 de fechamento, balanceados.

  ASCII-only de proposito: PowerShell 5.1 le .ps1 como ANSI e corromperia
  acentos escritos direto no arquivo.
#>

param([string]$Indice = "index.html")

$ErrorActionPreference = "Stop"

# Raiz do site: a pasta do script, se o indice estiver nela; senao, a pasta acima.
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot $Indice)) {
  $root = $PSScriptRoot
} else {
  $root = Split-Path -Parent $PSScriptRoot
}
$utf8 = New-Object System.Text.UTF8Encoding($false)

$ordem = @("FAIXA", "HEADER", "PAINEIS", "RODAPE", "ZAP", "TABBAR", "COOKIES")
$fim = @{
  FAIXA   = "FIMFAIXA"
  HEADER  = "FIMHEADER"
  PAINEIS = "FIMPAINEIS"
  RODAPE  = "FIMRODAPE"
  ZAP     = "FIMZAP"
  TABBAR  = "FIMTABBAR"
  COOKIES = "FIMCOOKIES"
}

# Qual link de menu e qual item da tabbar ficam ativos em cada pagina
$destinos = [ordered]@{
  "catalogo.html"  = @{ nav = "catalogo.html"; tabbar = "catalogo.html" }
  "produto.html"   = @{ nav = "catalogo.html"; tabbar = "catalogo.html" }
  "ajuda.html"     = @{ nav = "ajuda.html?doc=guia-de-escolha"; tabbar = "" }
  "politicas.html" = @{ nav = ""; tabbar = "" }
  "404.html"       = @{ nav = ""; tabbar = "" }
}

$caminhoIndice = Join-Path $root $Indice
if (-not (Test-Path -LiteralPath $caminhoIndice)) { throw "indice nao encontrado: $caminhoIndice" }
$fonte = [System.IO.File]::ReadAllText($caminhoIndice, $utf8)

function Extrair($txt, $ini, $fimMarcador) {
  $a = "<!--@$ini-->"
  $b = "<!--@$fimMarcador-->"
  $i = $txt.IndexOf($a)
  $j = $txt.IndexOf($b)
  if ($i -lt 0 -or $j -lt 0 -or $j -lt $i) { throw "marcadores $ini / $fimMarcador nao encontrados (ou fora de ordem) no indice" }
  $i = $i + $a.Length
  return $txt.Substring($i, $j - $i)
}

# Troca apenas o que fica entre os marcadores, mantendo os dois no lugar.
# Sem regex de proposito: o conteudo tem "R$" e outros simbolos que o regex
# interpretaria como sintaxe de substituicao.
function Substituir($txt, $ini, $fimMarcador, $novo, $pagina) {
  $a = "<!--@$ini-->"
  $b = "<!--@$fimMarcador-->"
  $i = $txt.IndexOf($a)
  $j = $txt.IndexOf($b)
  if ($i -lt 0 -or $j -lt 0 -or $j -lt $i) { throw "$pagina : marcadores $ini / $fimMarcador nao encontrados (ou fora de ordem)" }
  return $txt.Substring(0, $i + $a.Length) + $novo + $txt.Substring($j)
}

Write-Host "Lendo blocos de $Indice"
$conteudos = [ordered]@{}
foreach ($nome in $ordem) {
  $conteudos[$nome] = Extrair $fonte $nome $fim[$nome]
  Write-Host ("  {0,-9} {1,6} caracteres" -f $nome, $conteudos[$nome].Length)
}

Write-Host ""
Write-Host "Escrevendo nas paginas"

foreach ($pagina in $destinos.Keys) {
  $destino = Join-Path $root $pagina
  if (-not (Test-Path -LiteralPath $destino)) {
    Write-Host ("  {0,-18} nao existe, pulando" -f $pagina)
    continue
  }

  $html = [System.IO.File]::ReadAllText($destino, $utf8)
  $antes = $html

  foreach ($nome in $ordem) {
    $html = Substituir $html $nome $fim[$nome] $conteudos[$nome] $pagina
  }

  # Zera o aria-current herdado do indice antes de marcar o certo
  foreach ($par in @(
    @("nav__link", "index.html"),
    @("tabbar__item", "index.html"),
    @("nav__link", "catalogo.html"),
    @("tabbar__item", "catalogo.html"),
    @("nav__link", "ajuda.html?doc=guia-de-escolha")
  )) {
    $cls = $par[0]; $href = $par[1]
    $html = $html.Replace(('<a class="' + $cls + '" href="' + $href + '" aria-current="page">'),
                          ('<a class="' + $cls + '" href="' + $href + '">'))
  }

  $cfg = $destinos[$pagina]
  if ($cfg.nav) {
    $html = $html.Replace(('<a class="nav__link" href="' + $cfg.nav + '">'),
                          ('<a class="nav__link" href="' + $cfg.nav + '" aria-current="page">'))
  }
  if ($cfg.tabbar) {
    $html = $html.Replace(('<a class="tabbar__item" href="' + $cfg.tabbar + '">'),
                          ('<a class="tabbar__item" href="' + $cfg.tabbar + '" aria-current="page">'))
  }

  if ($html -ne $antes) {
    [System.IO.File]::WriteAllText($destino, $html, $utf8)
    Write-Host ("  {0,-18} ok" -f $pagina)
  } else {
    Write-Host ("  {0,-18} ja estava igual" -f $pagina)
  }
}

Write-Host ""
Write-Host "Verificacao"
$problemas = 0
foreach ($arquivo in (Get-ChildItem -LiteralPath $root -Filter *.html)) {
  $t = [System.IO.File]::ReadAllText($arquivo.FullName, $utf8)
  $atual = [regex]::Matches($t, 'aria-current="page"').Count
  $abre = [regex]::Matches($t, "<!--@(?!FIM)[A-Z]+-->").Count
  $fecha = [regex]::Matches($t, "<!--@FIM[A-Z]+-->").Count
  $esperado = $ordem.Count

  # Cada pagina deve ter exatamente um par abertura/fechamento por bloco
  $ok = ($abre -eq $esperado) -and ($fecha -eq $esperado)
  foreach ($nome in $ordem) {
    $nAbre = [regex]::Matches($t, [regex]::Escape("<!--@$nome-->")).Count
    $nFecha = [regex]::Matches($t, [regex]::Escape("<!--@$($fim[$nome])-->")).Count
    if ($nAbre -ne 1 -or $nFecha -ne 1) { $ok = $false }
  }
  if (-not $ok) { $problemas++ }

  Write-Host ("  {0,-18} aberturas: {1}   fechamentos: {2}   aria-current: {3}   {4}" -f $arquivo.Name, $abre, $fecha, $atual, $(if ($ok) { "ok" } else { "PROBLEMA" }))
}

if ($problemas -gt 0) {
  Write-Host ""
  Write-Host "$problemas pagina(s) com marcadores desbalanceados."
  exit 1
}
Write-Host ""
Write-Host "Tudo montado."
