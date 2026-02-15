# paper_template_agh

# IDE 
I use Visual studio Code with following plugins, and it geat tool for writing in LaTeX. In the repository I have included workspace for VSCode, and if you decide to use this editor, everything will be already set up to work

Extensions I use:
* james-yu.latex-workshop
* valentjn.vscode-ltex
* gruntfuggly.todo-tree


For code snippets I use package called `minted`. It is great, but to make it work you will need python, and module called `pygments`
to install it just type 

```{bash}
pip install Pygments
```

# Some tips for beginers
If you want to add a word in another language use `\foreignlanguage{english}{eng. \textit{word}}`. This will ensure that language tool will understand you changed the language, and it will not mark it as unknown word. The second benefit is that when LaTeX will lay down text, and it will have to break line, it will do so accordingly to the correct language roules

Every section should start on the odd number of pages. It is done automatically, so you do not need to do anything.
Because of the setup, floating objects like listings, images or tables, will not leak to next section (before every section there is a barier, that prevent rendering floating objects in next chapter)

To determine the odd page the page number is taken to account (it starts after table of contents), so check it before submiting yout thesis, and add empty page after table of contents if it is necessary
