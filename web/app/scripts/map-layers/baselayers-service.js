(function () {
    'use strict';

    /* Service for sharing baselayer configuration.
     */

    /* ngInject */
    function BaseLayersService($translate) {

        var module = {
            streets: streets,
            satellite: satellite,
            baseLayers: baseLayers
        };
        return module;

        function streets() {
            var layer = new L.tileLayer(
                // Local install patch: Carto basemaps (old and new URLs) now require an API key
                // and only return "API KEY REQUIRED" tiles. Use Esri's keyless street map instead.
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
                {
                    attribution: 'Tiles &copy; Esri &mdash; Esri, HERE, Garmin, &copy; OpenStreetMap contributors, and the GIS User Community',
                    maxZoom: 19,
                    detectRetina: false,
                    zIndex: 1
                }
            );
            return layer;
        }

        function satellite() {
            var layer = new L.tileLayer(
                '//server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                {
                    attribution: $translate.instant('MAP.ESRI_ATTRIBUTION'),
                    detectRetina: false,
                    zIndex: 1
                }            );
            return layer;
        }

        function baseLayers() {
            return [
                {
                    slugLabel: 'streets',
                    label: $translate.instant('MAP.STREETS'),
                    layer: streets()
                },
                {
                    slugLabel: 'satellite',
                    label: $translate.instant('MAP.SATELLITE'),
                    layer: satellite()
                }
            ];
        }
    }

    angular.module('driver.map-layers')
    .factory('BaseLayersService', BaseLayersService);
})();
