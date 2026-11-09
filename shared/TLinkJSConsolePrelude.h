#pragma once
#import <Foundation/Foundation.h>

// Keep one UTF16 lookahead unit so the native 4096-unit prefix can preserve
// surrogate boundaries and count truncation. Native admission remains final.
static inline NSString *TLinkJSConsolePrelude(){
    return @"(function(){\n"
        "  var slice = String.prototype.slice;\n"
        "  function convert(value){\n"
        "    try { return typeof value === 'string' ? value : JSON.stringify(value); }\n"
        "    catch(e) { return String(value); }\n"
        "  }\n"
        "  function fmt(args){\n"
        "    var out = '', limit = 4097;\n"
        "    for (var i = 0; i < args.length; ++i){\n"
        "      var text = convert(args[i]);\n"
        "      if (text != null && typeof text !== 'string'){\n"
        "        var rest = [text];\n"
        "        for (var j = i + 1; j < args.length; ++j) rest.push(convert(args[j]));\n"
        "        text = rest.join(' ');\n"
        "        if (i && out.length < limit) out += ' ';\n"
        "        if (out.length < limit) out += slice.call(text, 0, limit - out.length);\n"
        "        return out;\n"
        "      }\n"
        "      if (text == null) text = '';\n"
        "      if (i && out.length < limit) out += ' ';\n"
        "      if (out.length < limit) out += slice.call(text, 0, limit - out.length);\n"
        "    }\n"
        "    return out;\n"
        "  }\n"
        "  function emit(level, args){\n"
        "    if (!args.length){ _tlinkautoLog(level, ''); return; }\n"
        "    if (args.length === 1 && typeof args[0] === 'string' && args[0].length <= 4097){ _tlinkautoLog(level, args[0]); return; }\n"
        "    if (typeof _tlinkautoLogCanAccept === 'function' && !_tlinkautoLogCanAccept()) return;\n"
        "    _tlinkautoLog(level, fmt(args));\n"
        "  }\n"
        "  this.console = {\n"
        "    log: function(){ emit('log', arguments); },\n"
        "    info: function(){ emit('info', arguments); },\n"
        "    warn: function(){ emit('warn', arguments); },\n"
        "    error: function(){ emit('error', arguments); }\n"
        "  };\n"
        "})();";
}
