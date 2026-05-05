import gleam/dict
import gleam/http/response
import gleam/json
import gleam/list
import gleam/pair
import gleeunit
import liminal
import mist
import wisp.{type Request, type Response}
import wisp/wisp_mist

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn router_test() {
  // wisp_mist.handler(test_router())
  let secret_key = wisp.random_string(24)
  test_router()
  |> liminal.handler
  |> wisp_mist.handler(secret_key)
  |> mist.new
  |> mist.start
}

fn test_router() {
  liminal.router()
  |> liminal.after(compress_messages)
  |> liminal.default(fn(_, _) { wisp.not_found() })
  |> liminal.get(["example"], liminal.redirect("http://localhost"))
  |> liminal.get(["wibble"], fn(_, _) { wisp.ok() })
  |> liminal.get(["wobble"], fn(_, _) { wisp.ok() })
  |> liminal.post(["wibble"], fn(_, _) { wisp.ok() })
  |> liminal.post(["wobble"], fn(_, _) { wisp.bad_request("Not allowed") })
  |> liminal.context(at: ["example", ":id"], route: {
    liminal.router()
    |> liminal.before(prevent_non_logged_users)
    |> liminal.get(["static", "success"], liminal.proxy("http://localhost"))
    |> liminal.get(["static", "error"], liminal.proxy("http://localhost"))
    |> liminal.get(["code", "microsoft"], liminal.proxy("http://localhost"))
    |> liminal.get(["code", "google"], liminal.proxy("http://localhost"))
    |> liminal.post(["thing", "thing"], fn(_req, params) {
      dict.to_list(params)
      |> list.map(pair.map_second(_, json.string))
      |> json.object
      |> json.to_string
      |> wisp.json_response(200)
    })
  })
}

fn prevent_non_logged_users(
  req: Request,
  _params: liminal.Params,
  next: fn(Request) -> Response,
) -> Response {
  case list.key_find(req.headers, "authorization") {
    Error(_) -> wisp.bad_request("Non authorized user")
    Ok(content) if content != "test" -> wisp.bad_request("Non authorized user")
    Ok(_content) -> next(req)
  }
}

fn compress_messages(
  res: Response,
  _params: liminal.Params,
  next: fn(Response) -> Response,
) -> Response {
  res
  |> response.prepend_header("user-agent", "gleeunit")
  |> next
}
