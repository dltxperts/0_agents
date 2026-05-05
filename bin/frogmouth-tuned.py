"""frogmouth-tuned — Frogmouth markdown viewer with plan-friendly styling.

Runs as a real Python script (NOT via stdin heredoc) so that Textual can
read keyboard input from the terminal — feeding the Python source through
stdin closes stdin's TTY view and Textual aborts with ParseError on EOF.

Invoked by the sibling `frogmouth-tuned` bash wrapper which picks the
right Python interpreter (pipx venv first, system python3 fallback).
"""

from textual.widgets._markdown import Markdown as _Md

# Strip `dim` from the inline-code default and force a readable color.
_Md.DEFAULT_CSS = _Md.DEFAULT_CSS.replace(
    "text-style: bold dim;",
    "text-style: bold; color: gold;",
)

from frogmouth.app.app import MarkdownViewer, get_args

EXTRA_CSS = """
Omnibox { display: none; }

MarkdownH1 {
    background: #0cb6a9;
    color: $text;
    text-style: bold;
    border: wide $background;
    content-align: center middle;
    padding: 1;
}

MarkdownH2 {
    background: $primary-darken-2;
    color: $text;
    text-style: bold;
    border: wide $background;
    padding: 1;
}

MarkdownH3 {
    color: $text;
    text-style: bold underline;
    margin: 1 0;
    background: transparent;
    border: none;
}

MarkdownH4, MarkdownH5, MarkdownH6 {
    color: $text;
    text-style: bold underline;
}
"""


class TunedFrogmouth(MarkdownViewer):
    CSS = EXTRA_CSS


if __name__ == "__main__":
    TunedFrogmouth(get_args()).run()
