///|
pub extend HttpConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend HttpConfig with Eq::{not_equal, equal}

///|
pub extend HttpResponse with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend HttpResponse with Eq::{not_equal, equal}
