// EmojiSearch.js - Fast emoji parsing and filtering engine

function parseEmojis(raw) {
    if (!raw) return [];
    try {
        if (typeof raw === "string") {
            return JSON.parse(raw);
        } else if (Array.isArray(raw)) {
            return raw;
        }
    } catch (e) {
        console.error("Error parsing emojis JSON:", e);
    }
    return [];
}

function filterEmojis(emojis, filterText, limit) {
    if (!emojis || emojis.length === 0) return [];
    var max = limit || 1000;
    var query = (filterText || "").trim().toLowerCase();

    // If query is empty, return initial slice
    if (!query) {
        return emojis.slice(0, max);
    }

    // Strip leading/trailing colons like :fire: or :smile:
    if (query.length > 1 && query.startsWith(":")) {
        query = query.slice(1);
    }
    if (query.length > 1 && query.endsWith(":")) {
        query = query.slice(0, -1);
    }

    var exactMatches = [];
    var prefixMatches = [];
    var wordMatches = [];
    var containMatches = [];

    for (var i = 0; i < emojis.length; i++) {
        var item = emojis[i];
        var name = (item.n || "").toLowerCase();
        var subgroup = (item.s || "").toLowerCase();
        var group = (item.g || "").toLowerCase();

        if (name === query) {
            exactMatches.push(item);
        } else if (name.startsWith(query)) {
            prefixMatches.push(item);
        } else {
            // Check if any word starts with query
            var words = name.split(/[\s-]+/);
            var matchedWord = false;
            for (var w = 0; w < words.length; w++) {
                if (words[w].startsWith(query)) {
                    matchedWord = true;
                    break;
                }
            }

            if (matchedWord) {
                wordMatches.push(item);
            } else if (name.indexOf(query) !== -1 || subgroup.indexOf(query) !== -1 || group.indexOf(query) !== -1) {
                containMatches.push(item);
            }
        }

        if (exactMatches.length + prefixMatches.length + wordMatches.length + containMatches.length >= max * 1.5) {
            break;
        }
    }

    var combined = exactMatches.concat(prefixMatches, wordMatches, containMatches);
    return combined.slice(0, max);
}
