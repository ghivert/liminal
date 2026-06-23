import gleam/bool
import gleam/dict.{type Dict}
import gleam/function
import gleam/http
import gleam/list
import gleam/result
import wisp.{type Request, type Response}

pub opaque type Router {
  Router(
    pre_intercepters: List(PreIntercepter),
    post_intercepters: List(PostIntercepter),
    handlers: List(LiminalHandler),
    computed_handlers: Dict(http.Method, List(LiminalHandler)),
    default_handler: Handler,
  )
}

type LiminalHandler {
  LiminalHandler(at: List(String), method: http.Method, handler: Handler)
  LiminalRouter(at: List(String), router: Router)
}

type PreIntercepter =
  fn(Request, Params, fn(Request) -> Response) -> Response

type PostIntercepter =
  fn(Response, Params, fn(Response) -> Response) -> Response

pub type Handler =
  fn(Request, Dict(String, String)) -> Response

pub type Params =
  Dict(String, String)

pub fn router() -> Router {
  Router(
    pre_intercepters: [],
    post_intercepters: [],
    handlers: [],
    computed_handlers: dict.new(),
    default_handler:,
  )
}

pub fn redirect(to to: String) -> Handler {
  fn(_, _) { wisp.redirect(to) }
}

pub fn permanent_redirect(to to: String) -> Handler {
  fn(_, _) { wisp.permanent_redirect(to) }
}

pub fn default(
  router: Router,
  default_handler: fn(Request, Params) -> Response,
) -> Router {
  Router(..router, default_handler:)
}

pub fn before(
  router: Router,
  middleware: fn(Request, Params, fn(Request) -> Response) -> Response,
) -> Router {
  Router(..router, pre_intercepters: { [middleware, ..router.pre_intercepters] })
}

pub fn after(
  router: Router,
  middleware: fn(Response, Params, fn(Response) -> Response) -> Response,
) -> Router {
  Router(..router, post_intercepters: {
    [middleware, ..router.post_intercepters]
  })
}

pub fn context(router: Router, at at: List(String), router sub_router: Router) {
  Router(..router, handlers: {
    let sub_router = compute(sub_router)
    let is_sub_default_handler = sub_router.default_handler == default_handler
    let is_router_default_handler = router.default_handler == default_handler
    let sub_router =
      LiminalRouter(at:, router: {
        use <- bool.guard(when: !is_sub_default_handler, return: sub_router)
        use <- bool.guard(when: is_router_default_handler, return: sub_router)
        Router(..sub_router, default_handler: router.default_handler)
      })
    [sub_router, ..router.handlers]
  })
}

pub fn proxy(_to: String) -> Handler {
  fn(_, _) { todo }
}

pub fn get(router: Router, at: List(String), handler: Handler) {
  Router(..router, handlers: {
    let handler = LiminalHandler(at, http.Get, handler)
    [handler, ..router.handlers]
  })
}

pub fn post(router: Router, at: List(String), handler: Handler) {
  Router(..router, handlers: {
    let handler = LiminalHandler(at, http.Post, handler)
    [handler, ..router.handlers]
  })
}

// pub fn any(handler: Handler) {
//   todo
// }

pub fn handler(router: Router) -> fn(Request) -> Response {
  let router = compute(router)
  fn(request) {
    let parts = wisp.path_segments(request)
    handle_request(router, request, parts, dict.new())
  }
}

fn handle_request(router: Router, request, segments, params) {
  let method = get_request_method(request)
  let handlers = dict.get(router.computed_handlers, method)
  case result.try(handlers, find_matching_handler(_, segments, params)) {
    Error(_) -> respond(router, request, params, router.default_handler)
    Ok(#(params, [], LiminalHandler(handler:, ..))) ->
      respond(router, request, params, handler)
    Ok(#(_, [_, ..], LiminalHandler(..))) ->
      respond(router, request, params, router.default_handler)
    Ok(#(params, segments, LiminalRouter(..) as sub)) -> {
      use request, params <- respond(router, request, params)
      handle_request(sub.router, request, segments, params)
    }
  }
}

fn respond(router: Router, request, params, handler) {
  let Router(pre_intercepters:, post_intercepters:, ..) = router
  // Pre handlers.
  let handler = handler(_, params)
  let handler = build_pre_intercepter(pre_intercepters, params, handler)
  // Handler.
  let response = handler(request)
  // Post handlers.
  let handler = function.identity
  let handler = build_post_intercepter(post_intercepters, params, handler)
  handler(response)
}

fn build_pre_intercepter(
  pre_intercepters: List(PreIntercepter),
  params: Params,
  handler: fn(Request) -> Response,
) -> fn(Request) -> Response {
  case pre_intercepters {
    [] -> handler
    [intercepter] -> intercepter(_, params, handler)
    [intercepter, ..intercepters] -> {
      use request <- build_pre_intercepter(intercepters, params)
      intercepter(request, params, handler)
    }
  }
}

fn build_post_intercepter(
  post_interceptors: List(PostIntercepter),
  params: Params,
  handler: fn(Response) -> Response,
) -> fn(Response) -> Response {
  case post_interceptors {
    [] -> handler
    [intercepter] -> intercepter(_, params, handler)
    [intercepter, ..intercepters] -> {
      use response <- build_post_intercepter(intercepters, params)
      intercepter(response, params, handler)
    }
  }
}

fn find_matching_handler(handlers, segments, params) {
  use handler <- list.find_map(handlers)
  match_paths(handler, handler.at, segments, params)
}

fn match_paths(handler, expected, parts, params) {
  case expected, parts, handler {
    [], [], _ -> Ok(#(params, [], handler))
    _, [], _ -> Error(Nil)
    [], _, LiminalRouter(..) -> Ok(#(params, parts, handler))
    [], _, LiminalHandler(..) -> Error(Nil)
    [":" <> expect, ..expected], [segment, ..segments], _ ->
      dict.insert(params, expect, segment)
      |> match_paths(handler, expected, segments, _)
    [expect, ..rest], [segment, ..segments], _ if expect == segment ->
      match_paths(handler, rest, segments, params)
    _, _, _ -> Error(Nil)
  }
}

fn get_request_method(request: Request) {
  case request.method {
    http.Other(_) -> http.Other("")
    method -> method
  }
}

fn compute(router: Router) {
  let handlers = list.reverse(router.handlers)
  let computed_handlers = extract_handlers(handlers)
  Router(..router, computed_handlers:)
}

fn extract_handlers(handlers: List(LiminalHandler)) {
  dict.new()
  |> keep_method(handlers, http.Get)
  |> keep_method(handlers, http.Post)
  |> keep_method(handlers, http.Head)
  |> keep_method(handlers, http.Put)
  |> keep_method(handlers, http.Delete)
  |> keep_method(handlers, http.Trace)
  |> keep_method(handlers, http.Connect)
  |> keep_method(handlers, http.Options)
  |> keep_method(handlers, http.Patch)
  |> keep_method(handlers, http.Other(""))
}

fn keep_method(all_handlers, handlers, method: http.Method) {
  dict.insert(all_handlers, method, {
    use handler <- list.filter(handlers)
    case handler, method {
      LiminalRouter(..), _ -> True
      LiminalHandler(method: http.Other(_), ..), http.Other(_) -> True
      LiminalHandler(..), _ -> handler.method == method
    }
  })
}

fn default_handler(_, _) {
  wisp.not_found()
}
// pub fn proxy_to(request: Request, path: String, endpoint: Uri) {
//   wisp.read_body_bits(request)
//   |> loss.replace("Error decoding request")
//   |> result.try(fn(content) {
//     let config_with_timeout =
//       httpc.configure()
//       |> httpc.timeout(300_000)
//     request
//     |> request.set_path(path)
//     |> apply_uri_part(endpoint.host, request.set_host)
//     |> apply_uri_part(endpoint.port, request.set_port)
//     |> request.set_body(content)
//     |> httpc.dispatch_bits(config_with_timeout, _)
//     |> loss.httpc
//   })
//   |> result.map(clone_bits)
//   |> result.map_error(loss.log)
//   |> result.unwrap(wisp.internal_server_error())
// }

// fn copy_headers(
//   response: Response,
//   forward: response.Response(a),
//   header: String,
// ) -> Response {
//   let headers = list.filter(forward.headers, fn(h) { h.0 == header })
//   use response, #(key, value) <- list.fold(headers, response)
//   response.prepend_header(response, key, value)
// }

// fn clone_bits(res: response.Response(BitArray)) -> Response {
//   let body = bytes_tree.from_bit_array(res.body)
//   wisp.response(res.status)
//   |> response.set_body(wisp.Bytes(body))
//   |> copy_headers(res, "content-type")
//   |> copy_headers(res, "set-cookie")
//   |> copy_headers(res, "location")
// }

// fn apply_uri_part(request: b, part: Option(a), setter: fn(b, a) -> b) {
//   part
//   |> option.map(setter(request, _))
//   |> option.unwrap(request)
// }

// // CORS part

// /// Automatically manage CORS for any Wisp server.
// /// Allow correct origin according to environment.
// /// Allow GET, POST, PUT, PATCH, DELETE & OPTIONS request, as required by REST.
// /// Allow any header.
// /// Caches headers for 10 minutes.
// pub fn cors() -> cors.Cors {
//   let origins = select_origins()
//   cors.new()
//   |> list.fold(origins, _, cors.allow_origin)
//   |> cors.allow_method(http.Get)
//   |> cors.allow_method(http.Post)
//   |> cors.allow_method(http.Put)
//   |> cors.allow_method(http.Patch)
//   |> cors.allow_method(http.Delete)
//   |> cors.allow_method(http.Options)
//   |> cors.allow_header("*")
//   |> cors.allow_header("authorization")
//   // 600 is 10 minutes.
//   |> cors.max_age(600)
// }

// fn select_origins() {
//   case envoy.get("GLEAM_ENV") {
//     Ok("development") -> ["http://localhost:5173", "http://localhost:5174"]
//     Ok("staging") -> ["https://steerlab.dev", "https://admin.steerlab.dev"]
//     _ -> ["https://app.steerlab.ai", "https://admin.steerlab.ai"]
//   }
// }
