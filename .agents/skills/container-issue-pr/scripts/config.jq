def text: type == "string" and length > 0 and (contains("\u0000") | not);
def path: text and startswith("/") and (test("[\n\r\t]") | not);
def words: type == "array" and length > 0 and all(.[]; text);
def strings: type == "array" and all(.[]; text);
def relative: text and (startswith("/") | not) and (split("/") | all(.[]; . != ".." and . != ".git"));
def name: text and test("^[a-zA-Z0-9][a-zA-Z0-9_.-]*$");
.version == 1 and
(.source | path) and (.state_root | path) and (.lock_root | path) and
(.repository | text and test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) and
(.remote | name) and (.base | text) and (.branch_prefix | text) and
(.parallelism | type == "number" and . >= 1 and . <= 32 and floor == .) and
(.container.image | text) and (.container.network | name) and
(.container.cpus | type == "number" and . > 0) and (.container.memory | text) and
(.container.env_file | . == null or path) and
(.agent.argv | words) and
(.copy.exclude | strings) and (.copy.extra | type == "array" and all(.[]; relative)) and
(.host.resources | type == "array" and all(.[]; name)) and
(.host.env | type == "object" and all(to_entries[]; (.key | test("^[A-Za-z_][A-Za-z0-9_]*$")) and (.value | type == "string" and (contains("\u0000") | not)))) and
(.host.commands | type == "array" and length > 0 and all(.[]; (.name | text) and (.cwd | . == "." or relative) and (.argv | words))) and
(.pr.evidence | . == "required" or . == "waived") and
(.pr.waiver_reason | type == "string") and
(.pr.evidence != "waived" or (.pr.waiver_reason | length > 0))
