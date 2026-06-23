# Liminal

Liminal is a minimalistic router, supporting usual router syntax to define path
matchers, sub-router, and proxying to other servers. While simple pattern
matching is often enough to begin, you can quickly reach limits (like lacking of
logging middleware). Liminal go further those limits, by providing a correct,
fast router.

## Installation

```sh
gleam add liminal@1
```

## Getting Started

```gleam
fn main() {
  let secret_key = wisp.random_string(24)
  example_router()
  |> liminal.handler
  |> wisp_mist.handler(secret_key)
  |> mist.new
  |> mist.bind("localhost")
  |> mist.port(3300)
  |> mist.start
}

fn example_router() {
  liminal.router()
  |> liminal.after(compress_messages)
  |> liminal.default(default_forbidden)
  |> liminal.get(["example"], liminal.redirect("localhost"))
  |> liminal.get(["wibble"], fn(_, _) { wisp.ok() })
  |> liminal.get(["wobble"], fn(_, _) { wisp.ok() })
  |> liminal.post(["wibble"], fn(_, _) { wisp.ok() })
  |> liminal.post(["wobble"], fn(_, _) { wisp.bad_request("Not allowed") })
  |> liminal.context(at: ["example", ":id"], router: {
    liminal.router()
    |> liminal.before(prevent_non_logged_users)
    |> liminal.get(["dummy"], liminal.proxy("localhost"))
    |> liminal.post(["dummy"], fn(_req, params) {
      dict.to_list(params)
      |> list.map(pair.map_second(_, json.string))
      |> json.object
      |> json.to_string
      |> wisp.json_response(200)
    })
  })
}
```

## Remaining tasks

- [ ] Implement proxy support.
- [ ] Implement `any` handler.
- [ ] Implement custom method handlers.
- [ ] Improve documentation.

## Contributing

Every contributions are welcome. Feel free to open a Pull Request or to open
issues if you encounter any problem.
