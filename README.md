# Shadow Term

Shadow Term combines a GTK4/Vala terminal host with V Composer, a rich source editor with shell assistance and contextual prompt information. VTE owns terminal interpretation and PTY behavior; Composer owns editing, suggestions and presentation. Interactive fish uses Composer by default, while foreground programs retain ordinary terminal input.

- [Shadow Term](shadow-terminal/README.md): build, launch, tabs, appearance, prompt context and isolated verification.
- [V Composer](rich-input/README.md): reusable input widget, standalone demo and completion-provider contract.

Keep both directories together: Shadow Term builds the shared editor sources from `rich-input/`. Its normal terminal session needs no ClaudeVassal dependency; the optional CV demonstration has its own adapter requirements.

The source history for these components is retained from [Vibrant](https://github.com/visrosa/Vibrant). The earlier shell output-formatting plugin remains in that repository.
