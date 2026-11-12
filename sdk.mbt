///|
/// Stable business categories. Do not branch on SdkFailure.message.
/// ProcessingIncomplete includes parser/structural limits without a finer code.
#derive(Eq, Debug)
pub(all) enum FailureCode {
  InvalidConfiguration
  UnsupportedDocument
  ProcessingIncomplete
  IntegrityFailure
  InputLimitExceeded
  OutputLimitExceeded
  Cancelled
  WorkBudgetExceeded
  InternalFailure
  AuthorizationDenied
}

///|
pub extend FailureCode with Eq::{equal, not_equal}

///|
pub extend FailureCode with Debug::{to_repr}

///|
pub extend FailureCode with ToJson::{to_json}

///|
pub impl ToJson for FailureCode with fn to_json(self) -> Json {
  Json::string(self.label())
}

///|
pub fn FailureCode::label(self : FailureCode) -> String {
  match self {
    InvalidConfiguration => "invalid_configuration"
    UnsupportedDocument => "unsupported_document"
    ProcessingIncomplete => "processing_incomplete"
    IntegrityFailure => "integrity_failure"
    InputLimitExceeded => "input_limit_exceeded"
    OutputLimitExceeded => "output_limit_exceeded"
    Cancelled => "cancelled"
    WorkBudgetExceeded => "work_budget_exceeded"
    InternalFailure => "internal_failure"
    AuthorizationDenied => "authorization_denied"
  }
}

///|
#derive(Eq, Debug)
pub(all) enum SdkOperation {
  CleanDocument
  PrepareDocument
  ExecuteDocumentPlan
  VerifyDocument
  PreviewDocument
  AuthorizeDocument
  ExecuteAuthorizedDocument
}

///|
pub extend SdkOperation with Eq::{equal, not_equal}

///|
pub extend SdkOperation with Debug::{to_repr}

///|
pub extend SdkOperation with ToJson::{to_json}

///|
pub impl ToJson for SdkOperation with fn to_json(self) -> Json {
  Json::string(
    match self {
      CleanDocument => "clean_document"
      PrepareDocument => "prepare_document"
      ExecuteDocumentPlan => "execute_document_plan"
      VerifyDocument => "verify_document"
      PreviewDocument => "preview_document"
      AuthorizeDocument => "authorize_document"
      ExecuteAuthorizedDocument => "execute_authorized_document"
    },
  )
}

///|
/// Only an Err contains this diagnostic; never a partial document or receipt.
/// Message is explanatory and may change independently of the stable code.
#derive(Eq, Debug, ToJson)
pub(all) struct SdkFailure {
  code : FailureCode
  operation : SdkOperation
  message : String
}

///|
pub extend SdkFailure with Eq::{equal, not_equal}

///|
pub extend SdkFailure with Debug::{to_repr}

///|
pub extend SdkFailure with ToJson::{to_json}

///|
fn stopped_failure(
  operation : SdkOperation,
  control : WorkControl,
) -> SdkFailure? {
  match control.stop_kind() {
    Some(CancelRequested) =>
      Some({
        code: Cancelled,
        operation,
        message: control.stop_reason().unwrap(),
      })
    Some(AllowanceExhausted) =>
      Some({
        code: WorkBudgetExceeded,
        operation,
        message: control.stop_reason().unwrap(),
      })
    None => None
  }
}

///|
fn sdk_failure(
  error : Error,
  operation : SdkOperation,
  control : WorkControl,
) -> SdkFailure {
  match error {
    Refused(message) => { code: UnsupportedDocument, operation, message, }
    Invalid(message) => { code: IntegrityFailure, operation, message, }
    Incomplete(message) =>
      stopped_failure(operation, control).unwrap_or({
        code: ProcessingIncomplete,
        operation,
        message,
      })
    _ => { code: InternalFailure, operation, message: error.to_string(), }
  }
}

///|
fn sdk_preflight(
  input : Bytes,
  output : Bytes?,
  limits : Limits,
  control : WorkControl,
  operation : SdkOperation,
) -> SdkFailure? {
  limits.validate() catch {
    Refused(message) =>
      return Some({ code: InvalidConfiguration, operation, message, })
    error =>
      return Some({
        code: InternalFailure,
        operation,
        message: error.to_string(),
      })
  }
  if stopped_failure(operation, control) is Some(failure) {
    return Some(failure)
  }
  if input.length() > limits.input_bytes {
    return Some({
      code: InputLimitExceeded,
      operation,
      message: "input exceeds configured input_bytes",
    })
  }
  if output is Some(bytes) && bytes.length() > limits.output_bytes {
    return Some({
      code: OutputLimitExceeded,
      operation,
      message: "output exceeds configured output_bytes",
    })
  }
  None
}

///|
/// Default intake path: rebuild once and independently verify the actual bytes.
/// This includes the legacy implementation's verification, not an extra pass.
pub fn clean_document(
  input : Bytes,
  limits~ : Limits = Limits::default(),
  control~ : WorkControl = WorkControl::default(),
) -> Result[VerifiedRebuilt, SdkFailure] {
  let operation = CleanDocument
  if sdk_preflight(input, None, limits, control, operation) is Some(error) {
    return Err(error)
  }
  Ok(rebuild_verified(input, limits~, control~)) catch {
    error => Err(sdk_failure(error, operation, control))
  }
}

///|
/// Inspect/prepare without producing output; useful before caller confirmation.
pub fn prepare_document(
  input : Bytes,
  limits~ : Limits = Limits::default(),
  control~ : WorkControl = WorkControl::default(),
) -> Result[PreparedPlan, SdkFailure] {
  let operation = PrepareDocument
  if sdk_preflight(input, None, limits, control, operation) is Some(error) {
    return Err(error)
  }
  Ok(prepare(input, limits~, control~)) catch {
    error => Err(sdk_failure(error, operation, control))
  }
}

///|
/// Recomputes source bindings/plan constraints and verifies the actual result.
pub fn execute_document_plan(
  input : Bytes,
  plan : Json,
  limits~ : Limits = Limits::default(),
  control~ : WorkControl = WorkControl::default(),
) -> Result[VerifiedRebuilt, SdkFailure] {
  let operation = ExecuteDocumentPlan
  if sdk_preflight(input, None, limits, control, operation) is Some(error) {
    return Err(error)
  }
  Ok(rebuild_verified_with_plan(input, plan, limits~, control~)) catch {
    error => Err(sdk_failure(error, operation, control))
  }
}

///|
/// Archive path: reads actual output plus original; a supplied receipt is not proof.
pub fn verify_document(
  output : Bytes,
  original : Bytes,
  limits~ : Limits = Limits::default(),
  control~ : WorkControl = WorkControl::default(),
) -> Result[VerifiedReceipt, SdkFailure] {
  let operation = VerifyDocument
  if sdk_preflight(original, Some(output), limits, control, operation)
    is Some(error) {
    return Err(error)
  }
  Ok(verify_contract(output, original, limits~, control~)) catch {
    error => Err(sdk_failure(error, operation, control))
  }
}
