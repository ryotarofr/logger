const json = @import("json.zig");
pub fn main() !void {
    const pyfile = "logger.py";
    const root_id = "SKIC05008E004";
    const output_path = "logger_output.json";
    json.loggerZig(pyfile.ptr, pyfile.len, root_id.ptr, root_id.len, output_path.ptr, output_path.len);
}
