---
slug: notes-on-peter-naur-programming-as-theory-building
title: "Notes on Peter Naur: Programming as Theory Building"
date: 2021-10-23
authors: taylor
tags: [programming]
---

*[Source paper](https://pages.cs.wisc.edu/~remzi/Naur.pdf)*

**Abstract:** A programmer's main output is a theory. A program or program text is a manifestation of a part of that theory. Documentation and program text is insufficient to convey a theory. A program without its theory is dead, and should be replaced with a new theory.

![Construction](./10-23-21.jpg)

{/* truncate */}

The quality of work is based on the original programmer's theory of the problem and how well it matches his theory of the solution.

The quality of a later programmer's work is how well his theories match the previous programmer's theories.

Rather than pass on the design, we should pass on the theories driving the design.

---

Instead of considering a programmer to be a producer of a program and certain other texts, programming should be considered an activity to achieve a certain kind of insight, or form a theory of the matters at hand.

It's important to understand the theories behind a program, or it will lead to conflicts and frustrations.

---

Consider a program developed by group A is being extended by group B. Even with full documentation and discussions, group B will not understand the theory behind group A's work. By talking with group A, group B is able to modify their proposition to take advantage of group A's theory. Later another group without communication with group A makes the original powerful design ineffective. Documentation failed to carry some of the most important design ideas.

As a programmer, our job is to first understand the theories behind an existing system, before recommending our own theories of what the solution should've been.

I don't entirely agree with this statement (summarized): *Continued work on a large program requires the knowledge of a programmer closely and continuously connected to it.* After finishing the article, I changed my mind. I do agree with this statement. As much as I would like to believe that I am capable of documenting a project sufficiently to convey its theory to the next programmer.

---

Intelligence vs intelligent activity. Having information about something, versus having a theory about something, and recognizing and applying the theory in related aspects. My theory: knowing something is not enough, you must know how and where to apply it. E.g.: Applying Newton's Law Force = Mass × Acceleration to planets, etc. (it's not enough to know just that F=MA — what is F, M, A?). Hierarchy of data: Data → Information → Knowledge → Wisdom. Intelligence is having data, information, even knowledge, but intelligent activity is the wisdom of when to apply that knowledge, and where else it can be applied.

The dependence on a theory of how things relate makes it impossible to express the theory in terms of criteria or rules.

A programmer with the theory of the program is able to:
1. Explain how the solution relates to the affairs of the world it helps to handle
2. Explain why the program is the way it is — justifications for code decisions, perhaps with design rules, quantitative estimates, comparisons with alternatives, etc.
3. Make modifications easily, and make them where they should be made given the existing capabilities

---

Generally, modifying a complicated man-made construction is difficult and costly. Often buildings are demolished rather than modified. Yet, there is an expectation that it is easy to modify a program. In the Theory Building View, modifying a program is not simply changing the medium of text.

Building in flexibility to a program has a high cost, which may or may not even be useful in the future. Flexible solutions are fine if it is easy.

When modifying a program, a programmer must determine how the existing theory is similar, and what has changed in theory, in order to reflect the real world. This is where possessing the existing theory is crucial.

Problems arise when assuming programming consists of program text production, rather than an activity of theory building.

Without the underlying theory, modifications to a program will become inconsistent. Only a programmer with that theory will recognize the difference in character of various changes. The character of changes is vital to the long term viability of the program.

Program text production is one possibility manifested into a medium as part of the greater act of Theory Building.

---

A program dies when there is no longer a programmer possessing its theory in active control of the program. It may continue to be used, while the state of death only becomes evident when demands for modifications of the program cannot be intelligently answered. A program may be revived by a new programming team, but requires close contact with programmers who already possess the theory in order to gain an understanding of the program in the wider context of the relevant real world situations. Becoming familiar with the program text and other documentation is insufficient.

It is frustrating, costly, and time consuming to revive a program, and may lead to inconsistency as the new theory will likely differ from the original. The Theory Building View suggests discarding existing program text, and giving the new programmer team the opportunity to solve the given problem afresh.

---

> "On the Theory Building View the primary result of the programming activity is the theory held by the programmers."

> "What should you put into the documentation? That which helps the next programmer build an adequate theory of the program."

> "Experienced designers often start their documentation with just:
> - The metaphors
> - Text describing the purpose of each major component
> - Drawings of the major interactions between the major components"

[Discuss on Reddit](https://www.reddit.com/r/ExistentialCompany/comments/qecwxc/notes_on_peter_naur_programming_as_theory_building/)
