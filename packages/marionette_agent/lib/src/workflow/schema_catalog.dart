import 'dart:convert';

import '../protocol/protocol.dart';
import '../commands/wait_request.dart';

// Embedded so source and compiled CLI need no filesystem or network lookup.
Json workflowSchema([String? action]) {
  final schema = asJson(jsonDecode(_schema));
  final defs = asJson(schema[r'$defs']);
  final wait = asJson(asJson(defs['wait'])['properties']);
  (wait['state'] as Map)['enum'] = waitStates;
  (wait['pollIntervalMs'] as Map).addAll(<String, Object?>{
    'minimum': minimumWaitPollIntervalMs,
    'maximum': maximumWaitPollIntervalMs,
  });
  if (action == null) return schema;
  if (!workflowActions.contains(action)) invalid('Unknown workflow action');
  return {
    r'$schema': schema[r'$schema'],
    ...asJson(defs[action]),
    r'$defs': {'target': defs['target']},
  };
}

const workflowActions = ['snapshot', 'tap', 'fill', 'swipe', 'scroll', 'wait'];
const _schema = r'''{
  "type": "object",
  "properties": {
    "schemaVersion": {
      "type": "integer",
      "const": 1
    },
    "name": {
      "type": "string",
      "pattern": "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"
    },
    "description": {
      "type": "string",
      "maxLength": 256
    },
    "inputs": {
      "type": "object",
      "maxProperties": 32,
      "propertyNames": {
        "type": "string",
        "pattern": "^[A-Za-z][A-Za-z0-9_]{0,63}$"
      },
      "additionalProperties": {
        "type": "object",
        "properties": {
          "type": {
            "const": "string"
          },
          "required": {
            "type": "boolean"
          },
          "default": {
            "type": "string"
          },
          "sensitive": {
            "type": "boolean"
          }
        },
        "required": [
          "type"
        ],
        "additionalProperties": false
      }
    },
    "steps": {
      "type": "array",
      "minItems": 1,
      "maxItems": 100,
      "items": {
        "oneOf": [
          {
            "$ref": "#/$defs/snapshot"
          },
          {
            "$ref": "#/$defs/tap"
          },
          {
            "$ref": "#/$defs/fill"
          },
          {
            "$ref": "#/$defs/swipe"
          },
          {
            "$ref": "#/$defs/scroll"
          },
          {
            "$ref": "#/$defs/wait"
          }
        ]
      }
    }
  },
  "required": [
    "schemaVersion",
    "name",
    "steps"
  ],
  "additionalProperties": false,
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$defs": {
    "target": {
      "oneOf": [
        {
          "type": "object",
          "properties": {
            "key": {
              "type": "string",
              "minLength": 1
            }
          },
          "required": [
            "key"
          ],
          "additionalProperties": false
        },
        {
          "type": "object",
          "properties": {
            "identifier": {
              "type": "string",
              "minLength": 1
            }
          },
          "required": [
            "identifier"
          ],
          "additionalProperties": false
        },
        {
          "type": "object",
          "properties": {
            "text": {
              "type": "string",
              "minLength": 1
            }
          },
          "required": [
            "text"
          ],
          "additionalProperties": false
        },
        {
          "type": "object",
          "properties": {
            "type": {
              "type": "string",
              "minLength": 1
            }
          },
          "required": [
            "type"
          ],
          "additionalProperties": false
        }
      ]
    },
    "snapshot": {
      "type": "object",
      "properties": {
        "id": {
          "type": "string",
          "pattern": "^[A-Za-z][A-Za-z0-9_-]{0,63}$"
        },
        "action": {
          "const": "snapshot"
        }
      },
      "required": [
        "id",
        "action"
      ],
      "additionalProperties": false
    },
    "tap": {
      "type": "object",
      "properties": {
        "id": {
          "type": "string",
          "pattern": "^[A-Za-z][A-Za-z0-9_-]{0,63}$"
        },
        "action": {
          "const": "tap"
        },
        "target": {
          "$ref": "#/$defs/target"
        }
      },
      "required": [
        "id",
        "action",
        "target"
      ],
      "additionalProperties": false
    },
    "fill": {
      "type": "object",
      "properties": {
        "id": {
          "type": "string",
          "pattern": "^[A-Za-z][A-Za-z0-9_-]{0,63}$"
        },
        "action": {
          "const": "fill"
        },
        "target": {
          "$ref": "#/$defs/target"
        },
        "text": {
          "oneOf": [
            {
              "type": "object",
              "properties": {
                "literal": {
                  "type": "string"
                }
              },
              "required": [
                "literal"
              ],
              "additionalProperties": false
            },
            {
              "type": "object",
              "properties": {
                "input": {
                  "type": "string",
                  "pattern": "^[A-Za-z][A-Za-z0-9_]{0,63}$"
                }
              },
              "required": [
                "input"
              ],
              "additionalProperties": false
            }
          ]
        }
      },
      "required": [
        "id",
        "action",
        "target",
        "text"
      ],
      "additionalProperties": false
    },
    "swipe": {
      "type": "object",
      "properties": {
        "id": {
          "type": "string",
          "pattern": "^[A-Za-z][A-Za-z0-9_-]{0,63}$"
        },
        "action": {
          "const": "swipe"
        },
        "target": {
          "$ref": "#/$defs/target"
        },
        "direction": {
          "enum": [
            "left",
            "right",
            "up",
            "down"
          ]
        },
        "distance": {
          "type": "number",
          "exclusiveMinimum": 0
        }
      },
      "required": [
        "id",
        "action",
        "target",
        "direction"
      ],
      "additionalProperties": false
    },
    "scroll": {
      "type": "object",
      "properties": {
        "id": {
          "type": "string",
          "pattern": "^[A-Za-z][A-Za-z0-9_-]{0,63}$"
        },
        "action": {
          "const": "scroll"
        },
        "target": {
          "$ref": "#/$defs/target"
        },
        "direction": {
          "enum": [
            "left",
            "right",
            "up",
            "down"
          ]
        },
        "distance": {
          "type": "number",
          "exclusiveMinimum": 0
        }
      },
      "required": [
        "id",
        "action",
        "target",
        "direction"
      ],
      "additionalProperties": false
    },
    "wait": {
      "type": "object",
      "properties": {
        "id": {
          "type": "string",
          "pattern": "^[A-Za-z][A-Za-z0-9_-]{0,63}$"
        },
        "action": {
          "const": "wait"
        },
        "target": {
          "$ref": "#/$defs/target"
        },
        "state": {},
        "timeoutMs": {
          "type": "integer",
          "minimum": 1,
          "maximum": 30000
        },
        "pollIntervalMs": {
          "type": "integer"
        }
      },
      "required": [
        "id",
        "action",
        "target",
        "state"
      ],
      "additionalProperties": false
    }
  }
}''';
