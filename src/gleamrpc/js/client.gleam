import convert
import gleam/dynamic/decode
import gleam/javascript/promise
import gleam/result
import gleamrpc

pub type ClientError(error) {
  EncodeError(error: error)
  DecodeError(error: error)
  DataDecodeError(error: List(decode.DecodeError))
  TransportError(error: error)
}

/// A procedure client is a way to transmit the data of the procedure to execute and get back its data.  
/// You should not create procedure clients directly, but rather use libraries such as `gleamrpc_http_client`.
pub type ProcedureClientDefinition(transport_in, transport_out, error) {
  ProcedureClient(
    encode_data: fn(gleamrpc.ProcedureIdentity, convert.GlitrValue) ->
      Result(transport_in, error),
    send_and_receive: fn(transport_in) ->
      promise.Promise(Result(transport_out, error)),
    decode_data: fn(transport_out, convert.GlitrType) ->
      Result(convert.GlitrValue, error),
  )
}

pub fn call(
  client: ProcedureClientDefinition(transport_in, transport_out, error),
  procedure: gleamrpc.Procedure(params, return),
  params: params,
) -> promise.Promise(Result(return, ClientError(error))) {
  let identity =
    gleamrpc.ProcedureIdentity(
      procedure.name,
      procedure.router,
      procedure.type_,
    )
  let params_value = params |> convert.encode(procedure.params_type)

  case client.encode_data(identity, params_value) {
    Error(err) -> Error(EncodeError(err)) |> promise.resolve
    Ok(data) ->
      client.send_and_receive(data)
      |> promise.map(do_decoding(_, procedure, client))
  }
}

fn do_decoding(
  value: Result(out, error),
  procedure: gleamrpc.Procedure(params, return),
  client: ProcedureClientDefinition(in, out, error),
) -> Result(return, ClientError(error)) {
  use data <- result.try(value |> result.map_error(TransportError))
  use data <- result.try(
    client.decode_data(data, procedure.return_type |> convert.type_def)
    |> result.map_error(DecodeError),
  )

  data
  |> convert.decode(procedure.return_type)
  |> result.map_error(DataDecodeError)
}
