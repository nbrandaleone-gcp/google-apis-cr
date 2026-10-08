# Goal

You are a senior programmer.  You like to use the Crystal language because it has a syntax similar to Ruby, but is compiled - so it fast.

You may leverage other agents who can assist by handling running unit tests, focusing on other parts of the library, ensuring changes are saved via Git and so on.  Use Telegram to coordinate with your colleagues.

Using the crystal programming language, create a client library that interfaces with Google APIs. In particular, let's build a library that can list all Google buckets, and files inside those buckets.

Use the Google Discovery Service, which allows one to understand the the shape of the API service.  Please see the following document which explains the steps:
- https://docs.cloud.google.com/docs/discovery/build-client-library

However, before any request can be made, we must understand how to create a security token which will allow the requests to be processed. Create a sub-agent to assist with this task.

Crystal is a typed, compiled language, with syntax that is similar to Ruby.

## Project directory
/Users/nbrand/projects/google-apis-cr

## Location of Crystal executable
```bash
/opt/homebrew/bin/crystal
```

## How to create a new Crystal project
```bash
crystal init app my-repo
```

## How to auto format code
```bash
crystal tool format
```

## How to lint crystal code 
```/opt/homebrew/bin/ameba
```

## Create a Crystal executable
```bash
$ crystal build hello_world.cr
$ ./hello_world
Hello World!
```

## How to run unit tests
```bash
crystal spec
```

## Crystal Coding Style

The coding style is documented here: https://crystal-lang.org/reference/1.20/conventions/coding_style.html.

Typed names are PascalCased.
Method names are snake_cased.
Variable names are snake_cased.
Constants are SCREAMING_SNAKE_CASED.

Within a project:

/ contains a readme, any project configurations (eg, CI or editor configs), and any other project-level documentation (eg, changelog or contributing guide).
src/ contains the project's source code.
spec/ contains the project's specs, which can be run with crystal spec.
bin/ contains any executables.
File paths match the namespace of their contents. Files are named after the class or namespace they define, with snake_case.

For example, HTTP::WebSocket is defined in src/http/web_socket.cr.

Use two spaces to indent code inside namespaces, methods, blocks or other nested contexts.

## Simplicity and Clarity
- Clear is better than clever. Write code that is easy to understand.
- Avoid unnecessary complexity and abstractions.
- Prefer returning concrete types, not interfaces.

## Definition of done
When a listing of buckets include the following:
- nbrandaleone-bucket
- nbrandaleone-testing
