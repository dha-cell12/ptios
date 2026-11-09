    NSString *consolePrelude =
        @"(function(){\n"
         "  function fmt(args){ return Array.prototype.map.call(args, function(v){\n"
         "    try { if (typeof v === 'string') return v; return JSON.stringify(v); }\n"
         "    catch(e) { return String(v); }\n"
         "  }).join(' '); }\n"
         "  this.console = {\n"
         "    log: function(){ _tlinkautoLog('log', fmt(arguments)); },\n"
         "    info: function(){ _tlinkautoLog('info', fmt(arguments)); },\n"
         "    warn: function(){ _tlinkautoLog('warn', fmt(arguments)); },\n"
         "    error: function(){ _tlinkautoLog('error', fmt(arguments)); }\n"
         "  };\n"
         "})();";
