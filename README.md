<a href="https://jank-lang.org">
  <img src="https://media.githubusercontent.com/media/jank-lang/jank/main/.github/img/banner.png" alt="jank banner" />
</a>

<div align="center">
  <a href="https://clojurians.slack.com/archives/C03SRH97FDK" target="_blank"><img src="https://img.shields.io/badge/slack-%23jank-e01563.svg?style=flat&logo=slack&logoColor=fd893f&colorA=363636&colorB=363636" /></a>
  <a href="https://github.com/sponsors/jeaye" target="_blank"><img src="https://img.shields.io/github/sponsors/jeaye?style=flat&logo=github&logoColor=fd893f&colorA=363636&colorB=363636" /></a>
  <a href="https://twitter.com/jeayewilkerson" target="_blank"><img src="https://img.shields.io/twitter/follow/jeayewilkerson?style=flat&logo=x&logoColor=fd893f&colorA=363636&colorB=363636" /></a>
  <br/>
  <a href="https://github.com/jank-lang/jank/actions" target="_blank"><img src="https://img.shields.io/github/actions/workflow/status/jank-lang/jank/build.yml?branch=main&style=flat&logo=github&logoColor=fd893f&colorA=363636&colorB=363636" alt="CI" /></a>
  <a href="https://codecov.io/gh/jank-lang/jank" target="_blank"><img src="https://img.shields.io/codecov/c/github/jank-lang/jank?style=flat&logo=codecov&logoColor=fd893f&colorA=363636&colorB=363636" /></a>
</div>

# What is jank?

Most simply, jank is a [Clojure](https://clojure.org/) dialect on LLVM with C++ interop.
Less simply, jank is a general-purpose programming language which embraces the interactive,
functional, value-oriented nature of Clojure and the desire for the native
runtime and performance of C++. jank aims to be strongly compatible with
Clojure. While Clojure's default host is the JVM and its interop is with Java,
jank's host is LLVM and its interop is with C++.

For the current progress of jank and its usability, see the tables here: https://jank-lang.org/progress/

The current tl;dr for jank's usability is: **still getting there, but not ready for
use yet. Check back in a few months!**

# Installation

Currently, Jank doesn't have a stable versioning scheme so the only
version will be 0.1. As such, if you want a new version you'll have to
reinstall the package.

You can either:

```bash
brew install elken/jank/jank
```

To just install jank, or you can tap this repo using the below:

```bash
brew tap elken/jank
```

And use brew as normal:

```bash
brew install jank
```

Or, in a [`brew bundle`](https://github.com/Homebrew/homebrew-bundle) `Brewfile`:

```ruby
tap "elken/jank"
brew "jank"
```


# Documentation

For more on `brew`, check `brew help`.

For more on jank, check out [the repo](https://github.com/jank-lang/jank)
