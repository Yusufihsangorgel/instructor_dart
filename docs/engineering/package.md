# Package engineering rules: instructor_dart

Rules-Version: instructor_dart/8a198e1e1784c0e4c5e837fb101589b4f4ab2158ef0d6c29edfc823b5ce30f14
Core-Version: 1
Core-Digest: 1825fa7ff346dca23e65b1b3bf9b2e3e06959f1414bae9952d596d2f62f09b8f
Survey-Digest: f90f45c8a172068c3ed3b9488ba5a7cb4e58efa93c380d2d9a70b399349ec35e
Evidence-Revision: a171a60
Verified-Revision: unverified

Read CONTRIBUTING.md and docs/engineering/debt.json before editing.

A location written as `sha256:<hex>:<lines>` names a file by the SHA-256 of its repository-relative path.

## Current architecture
A single entry library (lib/instructor_dart.dart) fronts a small 'port and adapter' structure. Pure core: schema.dart (closed Schema hierarchy, JSON Schema generation, validation, normalize) and message.dart. Provider-independent contract (port): adapter.dart (LlmRequest, LlmResponse, abstract base LlmAdapter, AdapterException). Use case: instructor.dart (extract/extractRaw repair loop). Infrastructure: three HTTP provider adapters under lib/src/adapters/. The core and orchestration never see package:http. The adapters depend only on the port. The only runtime dependency is http. Integration with stream_struct is a dev dependency only. It runs through example/with_stream_struct.dart and a test that imports that example. AGENTS.md targets the agent that uses the package (Usage/Contracts/Mistakes/Where things live). Scanned HEAD: a171a60 (version 1.4.1).

## Layers and responsibilities
- lib/instructor_dart.dart: Exports every public name through explicit `show` lists. Carries the library dartdoc (9-27).
- lib/src/schema.dart, lib/src/message.dart: Closed Schema hierarchy: toJsonSchema, validate (SchemaViolation), normalize. Message/MessageRole value types. Neither file has imports.
- lib/src/adapter.dart: LlmRequest (copied collections), LlmResponse (toolCall/text/empty), abstract base LlmAdapter (complete, default close), AdapterException (status/transport + cause). Imports only message.dart.
- lib/src/instructor.dart: Instructor.extract/extractRaw: forced tool call request, local validation, retry with a repair prompt, ExtractionException and ExtractionAttempt history.
- lib/src/adapters/: HTTP wire format for three providers. Injected or owned http.Client, per-request timeout, and a funnel that turns every error into AdapterException.
- example/: Model-free and network-free demos (no_model_demo, mock_extract, with_stream_struct), plus local model demos with the _ollama.dart helper.
- test/: Unit tests over the public API, adapter tests with MockClient, freeze tests, and an Ollama test tagged e2e.

## Public API and dependency direction
The `show` list in lib/instructor_dart.dart exposes: AdapterException, LlmAdapter, LlmRequest, LlmResponse; three provider adapter classes, one per hosted API; ExtractionAttempt, ExtractionException, Instructor; Message, MessageRole; BooleanSchema, EnumSchema, IntegerSchema, ListSchema, NumberSchema, ObjectSchema, Schema, SchemaViolation, StringSchema (instructor_dart.dart:9-27). The single extension point is `abstract base class LlmAdapter`: outside code cannot implement it, only extend it (adapter.dart:78-83; AGENTS.md:61). Schema is sealed. Subtype constructors are private. Construction goes through the `Schema.object/string/...` factories (schema.dart:86-151). `_collectViolations` is a library-private hook (schema.dart:50-57). Deprecated: the unnamed `LlmResponse` constructor will be removed in 2.0.0 (adapter.dart:56-66).

adapters/*.dart → package:http + ../adapter.dart (+ ../message.dart) (for example gemini_adapter.dart:1-6). instructor.dart → adapter.dart, message.dart, schema.dart, dart:convert (instructor.dart:1-5); it sees neither a concrete adapter nor http. adapter.dart → message.dart (adapter.dart:1). schema.dart and message.dart import nothing. Direction: infrastructure → port → core, orchestration → port + core. package:http appears only inside lib/src/adapters/. stream_struct is a dev_dependency only (pubspec.yaml:34-37).

## Error, state and platform contracts
- Closed (sealed) Schema hierarchy. Construction uses static factories on the base class. Subtype constructors are private (schema.dart:29, 86-151, 167; commit 196cc4b).
- Library-private recursion hook `_collectViolations`. It works because all subtypes live in one file (schema.dart:50-57).
- `optional()` copy method on every schema type (schema.dart:182-188, 250-255 ...).
- Immutability: constructors copy caller collections and store them unmodifiable. test/freeze_test.dart locks this in (adapter.dart:9-17; schema.dart:83-95, 128-136).
- Adapter template: a trailing '/' on baseUrl is trimmed, http.Client is injected or owned (_ownsClient), `.timeout(timeout)`, transport error funnel, 2xx check, JSON decode, shape check, `on TypeError` wrapper, only an owned client closes on close (for example gemini_adapter.dart:31-43, 57-192).
- Single error type contract: AdapterException (status | transport + cause), ExtractionException(attempts) when validation runs out, ArgumentError on wrong arguments (adapter.dart:98-135; instructor.dart:25-39, 103-105).
- Three-state response: LlmResponse constructors named toolCall/text/empty (adapter.dart:39-70).
- Deprecation that names the removal version (adapter.dart:62-65).
- Sibling package integration through a dev dependency plus an example, locked in by a test that imports the example (pubspec.yaml:34-37; test/stream_validate_test.dart:4).
- The e2e test carries @Tags(['e2e']), skips itself when no server is present, and is excluded in CI (test/ollama_e2e_test.dart:1, 10-40; ci.yaml:23).

## Package rules
### instructor_dart/INS-01 [MUST]
Keep provider HTTP code in lib/src/adapters/. The schema, message and request/response types and the repair loop in lib/src/instructor.dart import neither package:http nor an adapter file.
Reason: The core and the use cases are independent of the provider. The dependency direction is infrastructure → port → core. A new provider or transport can be added without touching the core.
Evidence: lib/src/instructor.dart:1-5; lib/src/adapter.dart:1; lib/src/schema.dart and lib/src/message.dart (no imports); sha256:a0e51ea3ddb0:3
Evidence role: current-pattern
Existing violation: none

### instructor_dart/INS-02 [MUST]
Add a provider as a `final class` that extends the `LlmAdapter` base class, in its own file under lib/src/adapters/, exported by name from lib/instructor_dart.dart and tested against a mock HTTP client from package:http/testing.dart.
Reason: LlmAdapter is deliberately `base`: new methods with default bodies can reach all adapters in a minor release. Adapters are tested offline and deterministically.
Evidence: lib/src/adapter.dart:78-83; sha256:a0e51ea3ddb0:14; lib/instructor_dart.dart:11-13; test/adapters_test.dart:4-5; AGENTS.md:61
Evidence role: current-pattern
Existing violation: none

### instructor_dart/INS-03 [MUST]
Report every adapter failure as `AdapterException`: the status constructor for a non-2xx status or an unreadable 2xx body, `AdapterException.transport` when no response arrived, with the original error on `cause`. Callers catch one type.
Reason: This is the error contract frozen before 1.0. A caller catches all provider errors with a single `on AdapterException`.
Evidence: lib/src/adapter.dart:98-135; sha256:a0e51ea3ddb0:79-109,161-167; CHANGELOG.md:144-148; test/adapters_test.dart:398-408
Evidence role: current-pattern
Existing violation: none

### instructor_dart/INS-04 [MUST]
An adapter returns what the model produced (a tool call, text or nothing) and does not judge it. Validation, repair prompts and retries stay in `Instructor.extractRaw`.
Reason: Single responsibility: the wire format stays in the adapter, and the validation and repair loop stays in one place.
Evidence: lib/src/adapter.dart:72-77; lib/src/instructor.dart:95-171
Evidence role: current-pattern
Existing violation: none

### instructor_dart/INS-05 [MUST]
An adapter closes an HTTP client it created and never closes a client it was given.
Reason: Ownership rule. Instructor.close forwards to the adapter, and the socket of an adapter created inline can also close this way.
Evidence: sha256:a0e51ea3ddb0:29-30,170-174; lib/src/adapter.dart:88-95; lib/src/instructor.dart:51-59
Evidence role: current-pattern
Existing violation: none

### instructor_dart/INS-06 [MUST]
Add a schema type inside the sealed `Schema` hierarchy in lib/src/schema.dart: a private constructor, a static factory on `Schema`, `optional()`, `toJsonSchema()`, `_collectViolations()` and, when the Dart type can differ from the JSON type, `normalize()`.
Reason: The private recursion hook works only inside the same library. This is the shape of the current hierarchy.
Evidence: lib/src/schema.dart:29, 50-57, 86-151, 166-230, 289-303; commit 196cc4b (make concrete schema constructors library-private)
Evidence role: current-pattern
Existing violation: none

### instructor_dart/INS-07 [MUST]
When a request or schema type keeps a caller collection, its constructor copies it into an unmodifiable collection, and test/freeze_test.dart pins the copy.
Reason: After setup, a mutation by the caller must not change the request that will be sent or the validated schema.
Evidence: lib/src/adapter.dart:9-17; lib/src/schema.dart:83-95, 128-136; test/freeze_test.dart:5-24; commit 3eb1da3
Evidence role: current-pattern
Existing violation: none

### instructor_dart/INS-08 [MUST]
Export public names from lib/instructor_dart.dart with an explicit `show` list. Tests and examples import that library, not files under lib/src/.
Reason: The public API boundary stays visible in a single file. Nothing from lib/src leaks out.
Evidence: lib/instructor_dart.dart:9-27; test/*.dart imports (all package:instructor_dart/instructor_dart.dart)
Evidence role: current-pattern
Existing violation: none

### instructor_dart/INS-09 [MUST_NOT]
Do not add a runtime dependency for an example or for a sibling package. Use a dev dependency, an example file, and a test that imports the example.
Reason: A runtime dependency would also reach consumers that never use streaming. The pubspec comment justifies this explicitly.
Evidence: pubspec.yaml:32-37; test/stream_validate_test.dart:4
Evidence role: current-pattern
Existing violation: none

### instructor_dart/INS-10 [MUST]
A behavior change lands with a CHANGELOG entry, a test, and updated dartdoc on every member that describes the old behavior, in the same commit.
Reason: This is the repository practice (CHANGELOG and test go together in behavior commits). Counterexample: timeout behavior changed but three dartdoc comments still describe the old behavior (debt).
Evidence: commit 9cc948e, 810f488, a377092, 196cc4b (CHANGELOG and test changed in each); counterexample sha256:a0e51ea3ddb0:35-36
Evidence role: both
Existing violation: instructor_dart-D001

### instructor_dart/INS-11 [MUST]
Tests that need a live model carry `@Tags(['e2e'])`, skip when no server answers, and stay excluded from CI.
Reason: CI stays offline and deterministic. The e2e tests run locally with a 3 minute timeout.
Evidence: test/ollama_e2e_test.dart:1, 10-40; dart_test.yaml:1-3; .github/workflows/ci.yaml:23
Evidence role: current-pattern
Existing violation: none

### instructor_dart/INS-12 [SHOULD]
Deprecate public API before removing it: `@Deprecated` names the replacement and the major version that removes it.
Reason: This is the current deprecation format. Breaking removal happens only in a major release.
Evidence: lib/src/adapter.dart:56-66
Evidence role: current-pattern
Existing violation: none

### instructor_dart/INS-13 [MUST]
Every catch clause names a type. The transport call in an adapter catches `Exception` and wraps it in `AdapterException.transport`, and parsing catches `FormatException` or `TypeError`.
Reason: The typed catch principle in the shared Dart rules (dart-kod-kurallari.md J10). All documented transport types are Exceptions. A programming error (Error) must not be wrapped. The three current `catch (e)` sites are recorded as debt.
Evidence: sha256:a0e51ea3ddb0:98,141,161 (typed); counterexample sha256:a0e51ea3ddb0:81, sha256:7a72d20ef15c:98, gemini_adapter.dart:116
Evidence role: both
Existing violation: instructor_dart-D003

### instructor_dart/INS-14 [MUST]
New or changed public declarations carry a `///` comment.
Reason: The other five packages show no undocumented public declarations in this scan; this package shows 33 candidates. The undocumented extension point (`complete`) makes contribution harder.
Evidence: lib/src/adapter.dart:86 (`complete` belgesiz); sezgisel tarama: instructor_dart 33, rag_kit/llm_eval/vector_kit/stream_struct/mcp_probe 0
Evidence role: counterexample
Existing violation: instructor_dart-D004

### instructor_dart/INS-15 [MUST]
Concrete public classes are `final`. `LlmAdapter` is the one extension point, and `Schema` stays sealed.
Reason: In a frozen API, class modifiers keep evolution safe. Adding a new member does not break consumers.
Evidence: lib/src/message.dart:5; lib/src/adapter.dart:8, 39, 83, 106; lib/src/instructor.dart:8, 28, 46; lib/src/schema.dart:2, 29, 166, 238, 307, 358, 384, 414, 483
Evidence role: current-pattern
Existing violation: none

## Required verification
- Working directory: repository root; command: dart pub get; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:20.
- Working directory: repository root; command: dart format --output=none --set-exit-if-changed .; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:21.
- Working directory: repository root; command: dart analyze --fatal-infos; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:22.
- Working directory: repository root; command: dart test --exclude-tags e2e; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:23.
Not verified by the survey:
- The scan used the local HEAD (a171a60). Equality with origin (no network) and uncommitted changes were not measured. git status was not run because it can write to the index.
- Cognitive complexity scores (J2) were not measured. Candidates over 40 lines: instructor.dart:95-171 (extractRaw), gemini_adapter.dart:57-186 and the request methods of the other two adapters in lib/src/adapters/.
- Finding count with strict analyzer modes enabled: not measured. `dart analyze` writes to .dart_tool and the run was read-only.
- Whether tests pass today, coverage ratio, and web (dart2js/dart2wasm) results: `dart test` was not run.
- The count of undocumented public declarations comes from a heuristic awk scan (34 candidates, 1 known false positive: adapter.dart:66). The analyzer public_member_api_docs count was not measured.
- The status of the latest GitHub CI run and the pub.dev score were not measured (no network).

## Existing debt
The complete register is docs/engineering/debt.json.
- instructor_dart-D001 | small | sha256:a0e51ea3ddb0:35-36; sha256:7a72d20ef15c:40-41; lib/src/adapters/gemini_adapter.dart:48-49 | stale dartdoc / contract contradiction
  Fix: Fix the three dartdoc comments to say 'AdapterException.transport, cause TimeoutException'. Add a test per adapter with a MockClient that never completes and a short timeout.
  Closure: All three adapter dartdoc comments state that a timeout surfaces as AdapterException.transport with TimeoutException on cause. Each adapter has a test with a MockClient that never completes and a short timeout asserting that exception.
- instructor_dart-D002 | medium | sha256:a0e51ea3ddb0:26-30,46-109,161-174; sha256:7a72d20ef15c:23-28,69-123,152-165; gemini_adapter.dart:39-43, 75-142, 179-192 | duplicated logic
  Fix: An unexported shared helper under lib/src/adapters/ (JSON POST + transport funnel + shape guard). Keep only request body construction and response reading in the adapter. Safety net: adapters_test.dart and gemini_adapter_test.dart.
  Closure: A single unexported helper under lib/src/adapters/ performs the JSON POST, the transport funnel and the shape guard. The three adapters keep only request building and response reading and adapters_test.dart plus gemini_adapter_test.dart pass.
- instructor_dart-D003 | small | sha256:a0e51ea3ddb0:81; sha256:7a72d20ef15c:98; gemini_adapter.dart:116 | untyped catch
  Fix: Use `on Exception catch (e)`. Add a test showing that an Error thrown by a custom client propagates. Record it in the CHANGELOG.
  Closure: All three transport catch sites read on Exception catch. A test shows an Error thrown by a custom client propagates unwrapped and the CHANGELOG records the change.
- instructor_dart-D004 | medium | lib/src/adapter.dart:19-21, 68-69, 84, 86; lib/src/message.dart:6, 18-19; lib/src/instructor.dart:9, 29, 31, 47; lib/src/schema.dart:3, 30, 175-176, 246-247, 315-316, 387, 423-425; adapter `model` and `temperature` fields and constructors | undocumented public API
  Fix: Write the missing dartdoc comments. Lock against regression by adding the `public_member_api_docs` lint to analysis_options.yaml.
  Closure: Every public declaration listed in the item carries a /// comment, including LlmAdapter.complete. The public_member_api_docs lint is enabled in analysis_options.yaml and reports no findings.
- instructor_dart-D005 | medium | analysis_options.yaml:1-30 | configuration debt
  Fix: Simplify the template, turn on the strict modes, and close the resulting findings in the same change (finding count was not measured).
  Closure: analysis_options.yaml enables strict-casts, strict-inference and strict-raw-types with the template comments removed. Running dart analyze with those settings produces no findings.
- instructor_dart-D006 | small | .github/workflows/ci.yaml:20-23; lib/src/schema.dart:63-66, 232-237; lib/src/instructor.dart:87-91 | unverified platform claim
  Fix: Add `dart test -p chrome --exclude-tags e2e` to ci.yaml. Separate the tests that use dart:io (adapters_test.dart:2, 400; ollama_e2e_test.dart) with `@TestOn('vm')`.
  Closure: ci.yaml runs dart test -p chrome --exclude-tags e2e and the run passes. The test files that use dart:io carry @TestOn('vm').
- instructor_dart-D007 | small | sha256:7a72d20ef15c:54-67; lib/src/adapters/gemini_adapter.dart:59-73 | inconsistent behavior
  Fix: Pick one separator and one empty-conversation policy, and add tests to both adapters. If the difference is intentional, write the rationale in the dartdoc.
  Closure: Both adapters named in the location use one system-message separator and one empty-conversation policy. Tests in both adapter test files pin the choice or the dartdoc explains the intentional difference.
- instructor_dart-D008 | large | lib/src/adapter.dart:56-66; lib/src/instructor.dart:122-127 | planned removal (recorded)
  Fix: Remove the constructor in 2.0.0, turn LlmResponse into a three-case closed type, and delete the instructor.dart:122-127 branch.
  Closure: Version 2.0.0 removes the deprecated unnamed LlmResponse constructor and ships LlmResponse as a three-case closed type. The branch at instructor.dart:122-127 is gone and the package tests pass.
