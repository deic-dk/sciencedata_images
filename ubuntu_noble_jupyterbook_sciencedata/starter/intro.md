# My book

This is a starter book. Change it into your own: each `.md` or `.ipynb` file listed in
`_toc.yml` is a page, and the book is built again by itself a few seconds after you save
a change.

## Writing pages

Pages are Markdown (`.md`) files or Jupyter notebooks (`.ipynb`). Markdown pages can hold
mathematics, inline like $e^{i\pi} + 1 = 0$, or displayed:

$$
\int_0^1 x^2 \, dx = \frac{1}{3}
$$

and notes, warnings and the like:

```{note}
Edit this page in the Files app, or in a folder synced to your computer.
```

## The files in this folder

- `_config.yml` - the book's title, author and other settings
- `_toc.yml` - the table of contents: which pages, in which order
- `intro.md` - this page
- `notebook.ipynb` - a page made from a notebook; it is run when the book is built

To add a page, put a `.md` or `.ipynb` file here and list it in `_toc.yml`. Files not
listed there are left out of the book (`only_build_toc_files` in `_config.yml`).
