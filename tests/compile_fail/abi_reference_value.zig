//! FP-0011 case 20: the C ABI rejects the reference representation's value.

const Value = @import("fairpane").js.Runtime(.reference).Value;

export fn fairpane_probe_takes_value(value: Value) void {
    _ = value;
}

export fn fairpane_probe_returns_value() Value {
    return .undefined;
}

const Holder = extern struct {
    value: Value,
};

export fn fairpane_probe_holder(holder: *const Holder) void {
    _ = holder.value;
}
