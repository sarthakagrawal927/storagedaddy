(function initializeClarity(window, document) {
  if (window.location.hostname !== "storage.daddyrad.com") return;

  const projectId = "ymdrqo4jyc";
  window.clarity = window.clarity || function clarity() {
    (window.clarity.q = window.clarity.q || []).push(arguments);
  };

  const script = document.createElement("script");
  script.async = true;
  script.src = `https://www.clarity.ms/tag/${projectId}`;
  const firstScript = document.getElementsByTagName("script")[0];
  firstScript.parentNode.insertBefore(script, firstScript);
  window.clarity("set", "project_id", "storagedaddy");
})(window, document);
