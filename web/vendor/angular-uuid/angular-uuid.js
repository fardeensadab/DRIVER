/*
 * Drop-in replacement for ajsd/angular-uuid ~0.1 (repository removed from GitHub).
 * Added by the DRIVER local install patch set.
 *
 * Module: 'uuid'
 * Service: uuid4
 *   uuid4.generate() -> RFC 4122 version 4 UUID string
 *   uuid4.validate(str) -> true if str is a version 4 UUID
 */
(function () {
    'use strict';

    var VALID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

    function randomBytes(n) {
        var bytes = new Array(n), i;
        var c = (typeof window !== 'undefined') && (window.crypto || window.msCrypto);
        if (c && c.getRandomValues) {
            var arr = new Uint8Array(n);
            c.getRandomValues(arr);
            for (i = 0; i < n; i++) { bytes[i] = arr[i]; }
        } else {
            for (i = 0; i < n; i++) { bytes[i] = Math.floor(Math.random() * 256); }
        }
        return bytes;
    }

    function generate() {
        var b = randomBytes(16), hex = [], i;
        b[6] = (b[6] & 0x0f) | 0x40;
        b[8] = (b[8] & 0x3f) | 0x80;
        for (i = 0; i < 16; i++) { hex.push((b[i] + 0x100).toString(16).substr(1)); }
        return hex.slice(0, 4).join('') + '-' + hex.slice(4, 6).join('') + '-' +
            hex.slice(6, 8).join('') + '-' + hex.slice(8, 10).join('') + '-' +
            hex.slice(10, 16).join('');
    }

    angular.module('uuid', []).factory('uuid4', function () {
        return {
            generate: generate,
            validate: function (uuid) { return VALID.test(uuid); }
        };
    });
})();
