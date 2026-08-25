"use strict";

const form = document.getElementById("search");
const input = document.getElementById("query");
const notice = document.getElementById("tor-notice");
const cancel = document.getElementById("tor-cancel");
const proceed = document.getElementById("tor-continue");
const onionBase = "https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/";
let onionQuery = "";

function parseCommand(value) {
  const trimmed = value.trim();
  const match = /^@(noai|brave|google|onion)(?:\s+|$)(.*)$/i.exec(trimmed);
  return match ? { command: match[1].toLowerCase(), query: match[2].trim() } : null;
}

function navigate(base, query) {
  const url = new URL(base);
  if (query) {
    url.searchParams.set("q", query);
  }
  window.location.assign(url.href);
}

form.addEventListener("submit", event => {
  const parsed = parseCommand(input.value);
  if (!parsed) {
    return;
  }

  event.preventDefault();
  if (!parsed.query) {
    input.setCustomValidity("Enter a search after the command.");
    input.reportValidity();
    return;
  }

  input.setCustomValidity("");
  if (parsed.command === "noai") {
    navigate("https://noai.duckduckgo.com/", parsed.query);
    return;
  }

  if (parsed.command === "brave") {
    navigate("https://search.brave.com/search", parsed.query);
    return;
  }

  if (parsed.command === "google") {
    navigate("https://www.google.com/search", parsed.query);
    return;
  }

  onionQuery = parsed.query;
  notice.hidden = false;
  proceed.focus();
});

input.addEventListener("input", () => input.setCustomValidity(""));

cancel.addEventListener("click", () => {
  notice.hidden = true;
  onionQuery = "";
  input.focus();
});

proceed.addEventListener("click", () => {
  if (onionQuery) {
    navigate(onionBase, onionQuery);
  }
});
