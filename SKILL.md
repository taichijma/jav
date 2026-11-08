# javcli 的 Agent 技能

技能在 [`.agents/skills/javcli/SKILL.md`](.agents/skills/javcli/SKILL.md)。从 `.agents/skills` 读取项目技能的 Agent，打开本仓库时会用到它。内容包括安装、卸载、配置，以及全部子命令的用法。

在其它项目里使用时，把整个目录复制到当前 Agent 自己的技能根目录，不要只复制本文件：

```bash
mkdir -p "$AGENT_SKILLS_DIR"
rm -rf "$AGENT_SKILLS_DIR/javcli"
cp -a .agents/skills/javcli "$AGENT_SKILLS_DIR/javcli"
```

`AGENT_SKILLS_DIR` 是这个 Agent 已经在加载技能的目录。
