//! FP-0011 case 20: the C ABI rejects the tagged_index representation's value.

const Rt = @import("fairpane").js.Runtime(.tagged_index);
const Value = Rt.Value;

export fn fairpane_probe_takes_value(value: Value) void {
    _ = value;
}

export fn fairpane_probe_returns_value() Value {
    return Rt.undefined_value;
}

const Holder = extern struct {
    value: Value,
};

export fn fairpane_probe_holder(holder: *const Holder) void {
    _ = holder.value;
}
