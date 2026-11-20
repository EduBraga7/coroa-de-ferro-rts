# Coroa de Ferro — Decisões de design

Documento vivo. Em caso de dúvida sobre o que o jogo deve ser, vale o que está aqui.

## Objetivo
Um jogo **divertido para o próprio dono jogar**, solo. Não é projeto comercial nem multiplayer.

## Rumo atual: base-builder com ondas de inimigos
Antes era um RTS clássico contra bots. Como o jogo é só solo, mudamos: **você monta e defende a base, e os inimigos chegam em ondas.**
Mantém câmera RTS, construções, economia, torres e unidades. O bot deixa de ser um rival com base e vira a ameaça.

## Decisões fechadas

1. **Partida longa, sem duração fixa.** Dura o tempo que explorar, crescer e enfrentar os covis levar. Deve poder ser salva e continuada (ainda não implementado).
2. **Início lento.** Há um longo período de calmaria para construir antes da primeira onda.
3. **Ondas crescentes** em força e variedade, saindo dos covis.
4. **Vitória: destruir todos os covis inimigos.** Eles ficam espalhados pelo mapa, escondidos na névoa de guerra. Enquanto existirem, mandam ondas, e as ondas ficam mais fortes com o tempo.
5. **Exploração e recursos.** Os recursos melhores ficam longe da base. É preciso explorar para achá-los e para achar os covis. (Fácil de mudar depois se a vitória não agradar.)
6. **Sem eras e sem evoluções.** Todo o roster de unidades e construções está disponível desde o início. O limite é economia, população e tempo.
7. **Medieval realista.** Sem magia nem criaturas por enquanto.

## Em aberto
- Quantos covis e o tamanho do mapa.
- Se há aviso prévio antes de cada onda.
- Se os inimigos atacam só o Salão Real ou qualquer construção.
- Salvar/continuar partida (ainda não existe; a névoa de guerra já existe).
- O quanto os soldados do jogador importam, comparado a torres e muralhas.
- Camada roguelite depois (mapa e bônus sorteados a cada partida).
- Fantasia: continua fora, a menos que você peça.

## Código atual
- Eras já foram removidas.
- O Barão não tem mais base rival nem economia. `scripts/wave_director.gd` controla os **covis** (prédio `lair`), as guarnições e as ondas. `ai_controller.gd` só joga pelo jogador nas simulações (`--aivai` e `tools/simulate_match.gd`).
- Covis sorteados a cada partida do outro lado do rio, a 75 m ou mais da base e a 40 m ou mais entre si, escondidos na névoa. Perto de cada covil há guarda e uma mina de ouro rica (2400+), e as pedreiras próximas também rendem mais.
- Valores provisórios para as questões em aberto, só para o jogo funcionar. Ajustam-se em `WaveDirector.DIFFICULTY`, e nenhuma delas está decidida:
  - **Covis e mapa:** 2 no Fácil, 3 no Normal e 4 no Difícil, no mesmo mapa de 200 × 200 m.
  - **Aviso:** o HUD mostra a contagem até a próxima onda. As tropas se reúnem por 30 s no covil, e a saída da onda toca trompa e gera alerta.
  - **Alvo:** cada onda vai para a construção do jogador mais perto do covil, com preferência pelo Salão Real, e luta com o que encontrar no caminho. A cada 4 ondas (a partir da 4ª) há uma incursão rápida contra camponeses e pontos de entrega.
  - **Ritmo:** a 1ª onda chega aos ~13 min no Fácil, ~10 min no Normal e ~8 min no Difícil. Depois disso cada covil manda uma onda a cada ~6–7 min. As ondas começam pequenas e crescem cada vez mais rápido. Aríetes começam 16 min após a 1ª onda e capitães, 24 min após.
  - **Defesa do covil:** 6000 de vida e armadura alta, então espadas rendem pouco e aríetes derrubam rápido. A guarda cresce com o tempo. Atacado, o covil toca a trompa e convoca defensores do tamanho de uma onda, no máximo a cada 75 s.
- Derrota ao perder todos os Salões Reais e Castelos. Vitória ao destruir todos os covis.
- Ritmo medido com `tools/simulate_match.gd`, em que uma IA joga pelo jogador e já sabe onde estão os covis: no Normal ela vence perto dos 30 min, e uma IA fraca no Difícil perde perto dos 30 min. Uma pessoa, que precisa explorar, deve levar mais tempo. Falta testar jogando de verdade.

## Visual
Direção de arte: **tarde dourada de verão, medieval realista e acolhedora**. Primeiro a leitura clara do jogo, depois a beleza, sem pesar na GPU. A máquina-alvo é uma Radeon RX 550 com o renderizador Mobile.
- **Luz:** sol quente de lado, a 44° de altura, com sombras médias que não escondem as unidades. O céu frio clareia as sombras. O tonemapper é AgX, com uma LUT leve que deixa as sombras frias e as luzes quentes.
- **Névoa de guerra:** o inexplorado é uma bruma clara com volume, como um mar de nuvens. O que já foi explorado e está fora de visão ganha um véu frio e translúcido.
- **Vida no mapa:** sombras de nuvens passam devagar e as copas das árvores balançam ao vento. A grama 3D tem a cor do chão embaixo dela, e o campo tem manchas de grama seca e viçosa.
- **Qualidade gráfica:** [F9] alterna Alta, Equilibrada e Leve, e a escolha fica salva em `user://graficos.cfg`. Medido na RX 550 com a GPU livre, a Alta roda a ~96 FPS em 1600×900 e ~69 FPS em 1920×1080. A Leve roda a ~133 e ~96 FPS.
- **Código:** `scripts/world_look.gd` guarda os recursos compartilhados, `scripts/graphics_settings.gd` os presets, e os shaders ficam em `scripts/shaders/`. Para medir, use `tools/bench_render.gd`, que tira capturas e mede o custo por camada. Feche outros jogos antes: dividir a GPU invalida os números.

## Fora deste projeto
Um jogo de colônia/vila no estilo *RimWorld* ou *Banished* é uma ideia boa, mas **será um projeto separado**.
