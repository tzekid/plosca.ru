# Hello World

Date: 2019-01-01

Canonical: https://plosca.ru/hello_world

Hello World: first post by Ilie Ploscaru introducing the site and its themes.

---

Hello World
1 January 2019
TL;DR
Short rant about the website.
The website
With free time on my hands these holidays I’ve decided that it was about time to revamp my website. Learning to use an off the shelf static site generator
looked daunting, so I’ve decided to build my own
™. Goals
The main goals of this website was to put myself out there and learn to write for an audience. The main design choice for the website was: steal as much as possible from other people, and hope you have stolen enough so that people won’t pinpoint the source at first glance. Implementation
After I’ve look at how other’s built their websites, I decided to follow K.I.S.S.
and mainly use pandoc
’s markdown to html generation as a starting point. And it was awesome. Pandoc will simply take in some text file and turn it into anything you could possibly want. It even has embedded syntax highlighting out of the box! That right there made me happy that I wouldn’t have to depend on an external JS library for that functionality. With the website slowly evolving I needed some way to glue all the things together, and there came bash scripting into action. I ended up writing small scripts which did specific tasks, from glueing the navigation to each html file to recognising custom syntax and replacing these lines with a html for checkboxes that I really, really wanted to have. Lessons learned
I should definetly learn to use grep/sed/awk for text search and manipulation. Second lesson, which may be even more important is streams
in bash scripts. The time ‘compiling’ the whole site went from over 10 seconds to just about a second. # a sample line from `scripts/process.sh` scripts/add_checkboxes.sh
$1
|
pandoc
-s --toc -c style.css --katex |
\ scripts/refine.sh
>
$new_file
The next thing I discovered was entr
. It’s a tool that watches for file changes and performs commands you give it when one occurs. # automagically compile when a file in `src/` changes ls
src/* |
entr
-p ./compile.sh A goal on the todo list is only compiling the files that were changed, or react to edge cases when two or more files need changing. Lastly, something that’s in the works™ is automatically including the reading time of each article after the title. While implementing that I found wc
, a tool that prints character, word, line &c. count. Small things like this make your life easier. Thanks for reading so far and I hope you’ve found something useful here! Related
Prose
older poems and writing samples.
About
current profile, work focus, and contact links.
Generated context
View generated backlinks and similar pages.
