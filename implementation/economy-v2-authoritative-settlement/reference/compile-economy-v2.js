#!/usr/bin/env node
'use strict';

/*
 * This compiler is intentionally a narrow offline acceptance reference.  It
 * accepts one immutable source file by canonical path and exact file hash,
 * then emits a deterministic JSON baseline for a future separately-reviewed
 * authority core.  It does not create Lua, runtime, Y3, service, or ledger
 * artifacts.
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { TextDecoder } = require('util');

const FROZEN_INPUT = Object.freeze({
  relativePath: 'docs/物编/成长数值与经济裁决包/tables/economy-v2-resource-table.json',
  resourceTableFileSha256: '3288BD9CD1BFBB516DB4808EF002C45FECCF5F1C7F4C80499DB81E31B2F84EAE',
  documentVersion: 1,
  table: 'economy-v2-resource-table',
  resourceTableVersion: 'economy-v2',
  runtimeHandoff: false,
  productionGate: 'closed',
  compiledFormat: 'economy-v2-authoritative-settlement/offline-compiled-baseline/v1',
});

class CompilerError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function fail(code, message) {
  throw new CompilerError(code, message);
}

function isJsonWhitespace(character) {
  return character === ' ' || character === '\n' || character === '\r' || character === '\t';
}

/**
 * Parse JSON without JSON.parse's silent "last key wins" behavior.  The
 * decoder is deliberately small and complete for JSON: every object tracks
 * decoded key strings, so `"a"` and `"\\u0061"` are the same key.
 */
function parseJsonRejectingDuplicateKeys(text, label) {
  let index = 0;

  function syntax(message) {
    fail('JSON_PARSE_ERROR', `${label}: ${message} at UTF-16 offset ${index}`);
  }

  function skipWhitespace() {
    while (index < text.length && isJsonWhitespace(text[index])) {
      index += 1;
    }
  }

  function consume(expected) {
    if (text[index] !== expected) {
      syntax(`expected ${JSON.stringify(expected)}`);
    }
    index += 1;
  }

  function parseString() {
    consume('"');
    let value = '';
    while (index < text.length) {
      const character = text[index];
      index += 1;
      if (character === '"') {
        return value;
      }
      if (character === '\\') {
        if (index >= text.length) {
          syntax('unterminated escape sequence');
        }
        const escape = text[index];
        index += 1;
        if (escape === '"' || escape === '\\' || escape === '/') {
          value += escape;
        } else if (escape === 'b') {
          value += '\b';
        } else if (escape === 'f') {
          value += '\f';
        } else if (escape === 'n') {
          value += '\n';
        } else if (escape === 'r') {
          value += '\r';
        } else if (escape === 't') {
          value += '\t';
        } else if (escape === 'u') {
          const hex = text.slice(index, index + 4);
          if (!/^[0-9a-fA-F]{4}$/.test(hex)) {
            syntax('invalid unicode escape');
          }
          value += String.fromCharCode(Number.parseInt(hex, 16));
          index += 4;
        } else {
          syntax(`invalid escape \\${escape}`);
        }
        continue;
      }
      if (character.charCodeAt(0) < 0x20) {
        syntax('unescaped control character in string');
      }
      value += character;
    }
    syntax('unterminated string');
  }

  function parseNumber() {
    const remaining = text.slice(index);
    const match = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(remaining);
    if (!match) {
      syntax('invalid number');
    }
    index += match[0].length;
    const number = Number(match[0]);
    if (!Number.isFinite(number)) {
      syntax('number is outside the finite JSON range');
    }
    return number;
  }

  function parseLiteral(literal, value) {
    if (text.slice(index, index + literal.length) !== literal) {
      syntax(`expected ${literal}`);
    }
    index += literal.length;
    return value;
  }

  function parseArray() {
    consume('[');
    skipWhitespace();
    const array = [];
    if (text[index] === ']') {
      index += 1;
      return array;
    }
    while (true) {
      array.push(parseValue());
      skipWhitespace();
      if (text[index] === ']') {
        index += 1;
        return array;
      }
      consume(',');
      skipWhitespace();
    }
  }

  function parseObject() {
    consume('{');
    skipWhitespace();
    const object = Object.create(null);
    const seen = new Set();
    if (text[index] === '}') {
      index += 1;
      return object;
    }
    while (true) {
      if (text[index] !== '"') {
        syntax('object keys must be strings');
      }
      const key = parseString();
      if (seen.has(key)) {
        fail('DUPLICATE_JSON_KEY', `${label}: duplicate decoded JSON key ${JSON.stringify(key)}`);
      }
      seen.add(key);
      skipWhitespace();
      consume(':');
      skipWhitespace();
      object[key] = parseValue();
      skipWhitespace();
      if (text[index] === '}') {
        index += 1;
        return object;
      }
      consume(',');
      skipWhitespace();
    }
  }

  function parseValue() {
    skipWhitespace();
    const character = text[index];
    if (character === '"') {
      return parseString();
    }
    if (character === '{') {
      return parseObject();
    }
    if (character === '[') {
      return parseArray();
    }
    if (character === 't') {
      return parseLiteral('true', true);
    }
    if (character === 'f') {
      return parseLiteral('false', false);
    }
    if (character === 'n') {
      return parseLiteral('null', null);
    }
    if (character === '-' || (character >= '0' && character <= '9')) {
      return parseNumber();
    }
    syntax('expected a JSON value');
  }

  const result = parseValue();
  skipWhitespace();
  if (index !== text.length) {
    syntax('trailing non-whitespace content');
  }
  return result;
}

function stableJson(value) {
  if (value === null) {
    return 'null';
  }
  if (typeof value === 'string') {
    return JSON.stringify(value);
  }
  if (typeof value === 'boolean') {
    return value ? 'true' : 'false';
  }
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) {
      fail('UNSERIALIZABLE_VALUE', 'compiled baseline contains a non-finite number');
    }
    return Object.is(value, -0) ? '0' : JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(stableJson).join(',')}]`;
  }
  if (typeof value === 'object') {
    const keys = Object.keys(value).sort();
    return `{${keys.map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
  }
  fail('UNSERIALIZABLE_VALUE', `compiled baseline contains unsupported value type ${typeof value}`);
}

function readUtf8WithoutBom(filePath, label) {
  let bytes;
  try {
    bytes = fs.readFileSync(filePath);
  } catch (error) {
    fail('INPUT_READ_FAILED', `${label}: ${error.message}`);
  }
  if (bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    fail('INPUT_BOM_FORBIDDEN', `${label}: UTF-8 BOM is forbidden because the frozen hash covers raw file bytes`);
  }
  try {
    return { bytes, text: new TextDecoder('utf-8', { fatal: true }).decode(bytes) };
  } catch (error) {
    fail('INPUT_NOT_UTF8', `${label}: ${error.message}`);
  }
}

function requireObject(value, fieldName) {
  if (value === null || Array.isArray(value) || typeof value !== 'object') {
    fail('ALLOWLIST_INVALID', `${fieldName} must be a JSON object`);
  }
  return value;
}

function requireExact(value, expected, code, label) {
  if (value !== expected) {
    fail(code, `${label} must equal ${JSON.stringify(expected)}`);
  }
}

function parseArguments(argv) {
  const result = Object.create(null);
  for (let index = 0; index < argv.length; index += 1) {
    const name = argv[index];
    if (name !== '--input' && name !== '--output') {
      fail('ARGUMENT_INVALID', `unsupported argument ${JSON.stringify(name)}`);
    }
    if (Object.prototype.hasOwnProperty.call(result, name)) {
      fail('ARGUMENT_INVALID', `duplicate argument ${name}`);
    }
    const value = argv[index + 1];
    if (typeof value !== 'string' || value.length === 0 || value.startsWith('--')) {
      fail('ARGUMENT_INVALID', `${name} requires a non-empty path`);
    }
    result[name] = value;
    index += 1;
  }
  if (!result['--output']) {
    fail('ARGUMENT_INVALID', '--output is required; this compiler never writes a default baseline');
  }
  return result;
}

function normalizeForComparison(filePath) {
  return path.normalize(filePath).replace(/[\\/]+$/, '').toLocaleLowerCase('en-US');
}

function isWithin(parentPath, candidatePath) {
  const relative = path.relative(parentPath, candidatePath);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function resolveExisting(filePath, code, label) {
  try {
    return fs.realpathSync.native(filePath);
  } catch (error) {
    fail(code, `${label}: ${error.message}`);
  }
}

function assertPhysicalOutputDirectory(packageRoot, outputPath) {
  // This rejects reparse points observed during the check. Path-based Node
  // APIs cannot pin a Windows directory handle against concurrent replacement;
  // that adversary is explicitly outside this offline reference's trusted
  // filesystem boundary (see package-contract.json).
  const physicalPackageRoot = resolveExisting(packageRoot, 'OUTPUT_DIRECTORY_INVALID', 'offline acceptance package root');
  const requestedDirectory = path.dirname(outputPath);
  if (!isWithin(physicalPackageRoot, requestedDirectory)) {
    fail('OUTPUT_PATH_FORBIDDEN', 'compiled output must remain inside the physical offline acceptance package');
  }
  const relative = path.relative(physicalPackageRoot, requestedDirectory);
  let cursor = physicalPackageRoot;
  for (const segment of relative === '' ? [] : relative.split(path.sep)) {
    if (segment.length === 0 || segment === '.') continue;
    cursor = path.join(cursor, segment);
    let stat;
    try {
      stat = fs.lstatSync(cursor);
    } catch (error) {
      fail('OUTPUT_DIRECTORY_MISSING', `output parent directory must already exist: ${error.message}`);
    }
    if (!stat.isDirectory() || stat.isSymbolicLink()) {
      fail('OUTPUT_REPARSE_FORBIDDEN', 'output parent must be a physical directory, not a link or reparse point');
    }
    const physicalCursor = resolveExisting(cursor, 'OUTPUT_DIRECTORY_INVALID', 'output parent directory');
    if (!isWithin(physicalPackageRoot, physicalCursor)) {
      fail('OUTPUT_REPARSE_FORBIDDEN', 'output parent resolves outside the offline acceptance package');
    }
  }
  return { physicalPackageRoot, directory: cursor };
}

function writeAtomically(packageRoot, outputPath, content) {
  const { directory } = assertPhysicalOutputDirectory(packageRoot, outputPath);
  const temporaryPath = path.join(
    directory,
    `.${path.basename(outputPath)}.${process.pid}.${crypto.randomBytes(8).toString('hex')}.tmp`,
  );
  try {
    fs.writeFileSync(temporaryPath, content, { encoding: 'utf8', flag: 'wx' });
    // linkSync creates the final name only when it does not already exist.
    // Unlike renameSync on Windows it never overwrites a target inserted after
    // our initial existence check.
    assertPhysicalOutputDirectory(packageRoot, outputPath);
    fs.linkSync(temporaryPath, outputPath);
    fs.unlinkSync(temporaryPath);
  } catch (error) {
    try {
      if (fs.existsSync(temporaryPath)) {
        fs.unlinkSync(temporaryPath);
      }
    } catch (_) {
      // The original compiler error remains the useful failure.
    }
    fail('OUTPUT_WRITE_FAILED', error.message);
  }
}

function main() {
  const packageRoot = path.resolve(__dirname, '..');
  const workspaceRoot = path.resolve(packageRoot, '..', '..');
  const allowlistPath = path.join(packageRoot, 'contract', 'input-allowlist.json');
  const allowlistText = readUtf8WithoutBom(allowlistPath, 'input allowlist').text;
  const allowlist = requireObject(parseJsonRejectingDuplicateKeys(allowlistText, 'input allowlist'), 'input allowlist');
  const sourceAllowlist = requireObject(allowlist.source, 'input allowlist.source');
  const outputAllowlist = requireObject(allowlist.output, 'input allowlist.output');

  requireExact(allowlist.allowlist_schema_version, 1, 'ALLOWLIST_INVALID', 'allowlist_schema_version');
  requireExact(allowlist.package_status, 'offline-acceptance-reference-only', 'ALLOWLIST_INVALID', 'package_status');
  requireExact(allowlist.compiler_id, 'economy-v2-authoritative-settlement-offline-compiler-v1', 'ALLOWLIST_INVALID', 'compiler_id');
  requireExact(outputAllowlist.baseline_schema_version, 1, 'ALLOWLIST_INVALID', 'output.baseline_schema_version');
  requireExact(sourceAllowlist.relative_path, FROZEN_INPUT.relativePath, 'ALLOWLIST_DRIFT', 'source.relative_path');
  requireExact(sourceAllowlist.resource_table_file_sha256, FROZEN_INPUT.resourceTableFileSha256, 'ALLOWLIST_DRIFT', 'source.resource_table_file_sha256');
  requireExact(sourceAllowlist.document_version, FROZEN_INPUT.documentVersion, 'ALLOWLIST_DRIFT', 'source.document_version');
  requireExact(sourceAllowlist.table, FROZEN_INPUT.table, 'ALLOWLIST_DRIFT', 'source.table');
  requireExact(sourceAllowlist.resource_table_version, FROZEN_INPUT.resourceTableVersion, 'ALLOWLIST_DRIFT', 'source.resource_table_version');
  requireExact(sourceAllowlist.runtime_handoff, FROZEN_INPUT.runtimeHandoff, 'ALLOWLIST_DRIFT', 'source.runtime_handoff');
  requireExact(sourceAllowlist.production_gate, FROZEN_INPUT.productionGate, 'ALLOWLIST_DRIFT', 'source.production_gate');
  requireExact(outputAllowlist.format, FROZEN_INPUT.compiledFormat, 'ALLOWLIST_DRIFT', 'output.format');

  const expectedSourcePath = path.resolve(workspaceRoot, sourceAllowlist.relative_path);
  if (!isWithin(workspaceRoot, expectedSourcePath)) {
    fail('ALLOWLIST_INVALID', 'source.relative_path escapes the workspace');
  }
  const canonicalSourcePath = resolveExisting(expectedSourcePath, 'INPUT_READ_FAILED', 'allowlisted source');
  const argumentsValue = parseArguments(process.argv.slice(2));
  const requestedInputPath = path.resolve(process.cwd(), argumentsValue['--input'] || canonicalSourcePath);
  const canonicalRequestedInputPath = resolveExisting(requestedInputPath, 'INPUT_READ_FAILED', 'requested input');
  if (normalizeForComparison(canonicalRequestedInputPath) !== normalizeForComparison(canonicalSourcePath)) {
    fail('INPUT_PATH_DRIFT', 'only the canonical allowlisted economy-v2 source path is accepted');
  }

  const outputPath = path.resolve(process.cwd(), argumentsValue['--output']);
  if (!isWithin(packageRoot, outputPath)) {
    fail('OUTPUT_PATH_FORBIDDEN', 'compiled output must remain inside the offline acceptance package');
  }
  if (fs.existsSync(outputPath)) {
    fail('OUTPUT_ALREADY_EXISTS', 'refusing to overwrite an existing compiled baseline');
  }
  assertPhysicalOutputDirectory(packageRoot, outputPath);

  const source = readUtf8WithoutBom(canonicalSourcePath, 'economy-v2 source');
  const resourceTable = requireObject(parseJsonRejectingDuplicateKeys(source.text, 'economy-v2 source'), 'economy-v2 source');
  requireExact(resourceTable.version, sourceAllowlist.document_version, 'DOCUMENT_VERSION_MISMATCH', 'resource table version');
  requireExact(resourceTable.table, sourceAllowlist.table, 'TABLE_ID_MISMATCH', 'resource table table');
  requireExact(resourceTable.resource_table_version, sourceAllowlist.resource_table_version, 'RESOURCE_TABLE_VERSION_MISMATCH', 'resource_table_version');
  requireExact(resourceTable.runtime_handoff, sourceAllowlist.runtime_handoff, 'RUNTIME_HANDOFF_MISMATCH', 'runtime_handoff');
  requireExact(resourceTable.production_gate, sourceAllowlist.production_gate, 'PRODUCTION_GATE_MISMATCH', 'production_gate');

  const sourceSha256 = crypto.createHash('sha256').update(source.bytes).digest('hex').toUpperCase();
  requireExact(sourceSha256, sourceAllowlist.resource_table_file_sha256, 'SOURCE_SHA256_MISMATCH', 'source SHA-256');

  const baseline = {
    baseline_schema_version: outputAllowlist.baseline_schema_version,
    compiler_id: allowlist.compiler_id,
    format: outputAllowlist.format,
    package_status: allowlist.package_status,
    source: {
      relative_path: sourceAllowlist.relative_path,
      resource_table_version: resourceTable.resource_table_version,
      resource_table_file_sha256: sourceSha256,
      runtime_handoff: resourceTable.runtime_handoff,
      production_gate: resourceTable.production_gate,
    },
    resource_table: resourceTable,
  };
  const content = `${stableJson(baseline)}\n`;
  writeAtomically(packageRoot, outputPath, content);
  process.stdout.write(`economy-v2 compiled baseline: ${path.relative(packageRoot, outputPath)}\n`);
}

try {
  main();
} catch (error) {
  const code = error instanceof CompilerError ? error.code : 'UNEXPECTED_ERROR';
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`compile-economy-v2: ${code}: ${message}\n`);
  process.exitCode = 1;
}
