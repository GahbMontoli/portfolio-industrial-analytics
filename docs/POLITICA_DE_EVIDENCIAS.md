# Política de evidências, pesquisa e uso de fontes

## Regra geral

Toda afirmação factual externa usada nos projetos deve ter uma fonte registrada.
Preferência, nesta ordem:

1. norma, órgão oficial, documentação do fabricante ou conjunto oficial;
2. artigo revisado por pares, tese ou dissertação institucional;
3. relatório técnico com método publicado;
4. vaga ou página de mercado usada apenas como evidência observacional;
5. conteúdo secundário, somente para descoberta e nunca como única base técnica.

## Registro mínimo

- título e autores/organização;
- URL ou DOI;
- data de publicação/versão;
- data de acesso;
- tipo da fonte;
- afirmação sustentada;
- método ou população, quando houver;
- limitações;
- licença ou restrição de uso, quando relevante.

## Regras de interpretação

- uma vaga não representa todo o mercado;
- uma revisão sistemática orienta lacunas, mas não valida o nosso software;
- uma norma inspira vocabulário somente dentro do escopo licenciado e lido;
- dado meteorológico externo não representa ambiente interno de equipamento;
- resultado sintético não é convertido em economia, falha evitada ou causalidade;
- correlação deve ser chamada de associação;
- toda transformação deve manter a origem e o método;
- valores ausentes não viram zero sem justificativa;
- resultado contrário à hipótese permanece no relatório.

## Critério para artigos e trabalhos acadêmicos

Cada estudo do portfólio deve declarar:

- pergunta e hipótese antes da análise;
- variáveis, unidade, frequência e janela;
- população/amostra e critérios de inclusão;
- qualidade, ausências e exclusões;
- análise planejada e incerteza;
- versão do código, semente e hash dos dados;
- limitações e ameaças à validade;
- separação entre conclusão do software e conclusão sobre o mundo real.

## Proveniência dos artefatos locais

O `config/source-lock.json` é a lista versionada das fontes aceitas pela carga
analítica. O contrato atual cobre exatamente 10 artefatos de 3 repositórios
públicos e registra caminho portável, SHA-256, classe de evidência, papel,
repositório, commit e método de verificação.

Antes da consolidação, `scripts/Test-PortfolioBiSourceLock.ps1` deve:

- conferir a bijeção entre o lock e os arquivos efetivamente consumidos;
- rejeitar origem, commit, caminho, classe de evidência ou hash divergente;
- confirmar o commit contra a referência local `origin/main`, sem executar
  `fetch` implicitamente;
- preservar `synthetic`, `official_raw`, `lab_observed`, `field_observed` e
  `derived` como classes distintas;
- registrar, sem ocultar, HEAD atual e estado limpo/sujo de cada árvore.

Uma árvore suja não invalida automaticamente bytes reproduzidos ou travados a
um commit anterior. O artefato só entra quando seu hash coincide com o lock e o
commit travado existe e é ancestral da referência pública local; qualquer
divergência bloqueia a carga. O método de verificação registrado descreve como
o snapshot foi estabelecido, sujeito aos limites declarados. O resultado local
é `data/curated/source-lock-validation.json` e não deve ser confundido com dado
de campo ou validação do Power BI.

A maioria dos arquivos gerados é ignorada nos repositórios de origem. Portanto,
o lock publica hashes e metadados, não os próprios bytes. Ele identifica o
snapshot exato revisado, mas não constitui prova criptográfica de qual binário
executou o exportador. Métodos como `reproduced_from_commit`,
`manifest_hash_chain`, `git_blob_at_commit` e `validated_export_snapshot` devem
continuar distintos e acompanhados de suas limitações.

## Uso de IA

IA pode ajudar a localizar, classificar e resumir fontes, mas DOI, título,
resultado e conclusão devem ser verificados na fonte. Nenhuma referência gerada
sem verificação entra em artigo, README ou relatório.
