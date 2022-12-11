# Overview

Docker image with:
* VS Studio Code Server
* Rust 1.65.0
* AFL

# Building

Run: `docker build -t vs-code-with-rust-and-afl .`

# Credits

This is mostly based on the AFL++ Dockerfile, but elements from the VS Code Server Dockerfile were added as well.

# Running

Try something like: `docker run --rm -ti -p 3000:3000 vs-code-with-rust-and-afl` You should then see a few messages on your terminal, including a line like: `Web UI available at http://localhost:3000/?tkn=84e28781-89a1-4bd6-b483-8fe6ebf3d8d2` Visit this URL to access VS Code in your browser.