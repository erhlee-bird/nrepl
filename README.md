# NRepl

An Elixir nREPL client.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `nrepl` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nrepl, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/nrepl](https://hexdocs.pm/nrepl).

## Usage

Start an iex session with the environment variables:

- NREPL_HOST (defaults to "127.0.0.1")
- NREPL_PORT

```bash
NREPL_PORT=33685 iex -S mix
```

```elixir
Interactive Elixir (1.12.3) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)>
14:48:49.195 [debug] nREPL session alive: ec10b34c-b385-4084-806a-1f9dd6dbfc83
pid = :poolboy.checkout(:nrepl)
#PID<0.239.0>
iex(2)> pid |> NRepl.Connection.send_msg(:eval, %{code: ~s<(+ 1 2)>}) |> Stream.map(&IO.inspect/1) |> Stream.run()
%{
  "id" => "1b4333b5-fd0d-43e4-b9a5-8daf4ab56856",
  "ns" => "user",
  "session" => "e93c44c3-6fc4-4d62-83cc-6fa82d9a9852",
  "value" => "3"
}
%{
  "id" => "1b4333b5-fd0d-43e4-b9a5-8daf4ab56856",
  "session" => "e93c44c3-6fc4-4d62-83cc-6fa82d9a9852",
  "status" => ["done"]
}
:ok
iex(3)>
```

## License

Copyright 2019 Ben Damman

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
