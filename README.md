# 👑 Coroa de Ferro: Crônicas da Fronteira

RTS (estratégia em tempo real) medieval em **3D**, feito em **Godot 4.7.2** (renderer *Mobile*), com modelos e texturas procedurais gerados via **Blender 5.2** e scripts Python.

Você comanda o seu reino contra uma IA rival: colete ouro e madeira, construa sua base, treine tropas, avance de era e destrua a base inimiga.

## ✨ Recursos

- **Economia**: camponeses coletam **ouro** (minas) e **madeira** (árvores), com limite de população (máx. 80).
- **Construções**: Casa, Quartel, Torre de Vigia e Salão Real (Town Center).
- **Unidades**: Camponês, Espadachim, Arqueiro e Paladino (cavalaria), com projéteis para unidades à distância.
- **Evolução de era**: *Era Real* (250 ouro + 200 madeira) para desbloquear melhorias.
- **IA inimiga** (`ai_controller.gd`) que expande a economia, constrói e ataca.
- **Mapa com rio e pontes**, terreno com shader próprio e água animada.
- **Câmera RTS** com pan, zoom, órbita e seguir unidade.
- **HUD completo** com painel de comandos, atalhos de teclado e grupos de controle.
- **SFX procedurais** gerados em código (`sfx_manager.gd`), sem arquivos de áudio.
- **Cores de time** aplicadas dinamicamente nos materiais dos modelos.

## 🎮 Controles

| Ação | Tecla / Mouse |
|---|---|
| Selecionar / caixa de seleção | Botão esquerdo (arrastar) |
| Mover / atacar / coletar | Botão direito |
| Adicionar à seleção | `Shift` + clique |
| Grupos de controle | `1`–`5` |
| Mover câmera | `W A S D` / setas |
| Girar câmera | `Alt` ou `Shift` + botão do meio / `Z` `C` |
| Seguir unidade selecionada | `F` |
| Centralizar na base | `Espaço` / `Home` |
| Alternar seleção de tipo | `Tab` |
| Cancelar | `Esc` |
| Pausar | `P` |
| Ajuda | `F1` |
| Marcadores de câmera | `F2` `F3` `F4` |

**Comandos de produção/construção** (aparecem no painel inferior): `Q` `E` `R` `T` conforme o edifício ou unidade; `G` coletar, `X` atacar-mover / cancelar fila, `V` parar.

## 🚀 Como rodar

1. Instale o [Godot 4.7.x](https://godotengine.org/download).
2. Clone o repositório:
   ```bash
   git clone https://github.com/EduBraga7/coroa-de-ferro-rts.git
   ```
3. Abra o Godot → **Import** → selecione `project.godot`.
4. Pressione **F5** (cena principal: `scenes/main.tscn`).

## 🧪 Teste automatizado

Verificação E2E headless do projeto:

```bash
godot --headless --path . --script tools/verify_project.gd
```

## 📁 Estrutura

```
├── project.godot
├── scenes/main.tscn          # cena principal
├── scripts/                  # lógica do jogo (GDScript)
│   ├── game_manager.gd       # recursos, seleção, comandos, eras
│   ├── unit.gd               # unidades, estados, combate, pathfinding de pontes
│   ├── building.gd           # construções e filas de produção
│   ├── ai_controller.gd      # IA inimiga
│   ├── hud.gd                # interface e atalhos
│   ├── rts_camera.gd         # câmera RTS
│   ├── projectile.gd, resource_node.gd, sfx_manager.gd, main.gd
│   └── shaders/              # terrain.gdshader, water.gdshader
├── assets/
│   ├── models/               # .glb + texturas PBR
│   ├── textures/             # terreno
│   └── blender/              # fontes .blend e previews
├── tools/                    # geradores Python (Blender) + verify_project.gd
└── .claude/skills/           # skills de gamedev para agentes de IA
```

## 🛠️ Geração de assets

Os modelos são produzidos por scripts em `tools/` (rodar com o Blender 5.2 em modo *background*):

- `generate_blender_assets.py` – construções, props e recursos
- `generate_unit_assets.py` – unidades
- `generate_terrain_textures.py` – texturas do terreno

## 🤖 Skills para agentes de IA

O projeto inclui, em [`.claude/skills/`](.claude/skills/), as **79 skills + router** do repositório
[awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills)
(licença Apache-2.0, ver `LICENSE-awesome-gamedev-agent-skills`). Agentes como o Claude Code
carregam automaticamente as skills de Godot/GDScript, física, shaders, UI, IA etc. ao trabalhar no jogo.

## 📜 Licença

Código e assets do jogo: defina a licença desejada. As skills em `.claude/skills/` mantêm a licença Apache-2.0 original.
