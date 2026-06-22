exports.formatPercent = function(value) {
  return Math.round(value || 0) + "%";
};

exports.describeDevice = function(info, battery) {
  return (info.model || "unknown") + " battery " + exports.formatPercent(battery.level);
};
