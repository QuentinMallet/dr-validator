{ lib, beamPackages, overrides ? (x: y: {}) }:

let
  buildRebar3 = lib.makeOverridable beamPackages.buildRebar3;
  buildMix = lib.makeOverridable beamPackages.buildMix;
  buildErlangMk = lib.makeOverridable beamPackages.buildErlangMk;

  self = packages // (overrides self packages);

  packages = with beamPackages; with self; {
    bypass = buildMix rec {
      name = "bypass";
      version = "2.1.0";

      src = fetchHex {
        pkg = "bypass";
        version = "${version}";
        sha256 = "d9b5df8fa5b7a6efa08384e9bbecfe4ce61c77d28a4282f79e02f1ef78d96b80";
      };

      beamDeps = [ plug plug_cowboy ranch ];
    };

    certifi = buildRebar3 rec {
      name = "certifi";
      version = "2.15.0";

      src = fetchHex {
        pkg = "certifi";
        version = "${version}";
        sha256 = "b147ed22ce71d72eafdad94f055165c1c182f61a2ff49df28bcc71d1d5b94a60";
      };

      beamDeps = [];
    };

    cowboy = buildErlangMk rec {
      name = "cowboy";
      version = "2.16.1";

      src = fetchHex {
        pkg = "cowboy";
        version = "${version}";
        sha256 = "b8ea4dd317a043e3177ec840cfa3bcb47cfb41035d3abb24d954dc7d51def399";
      };

      beamDeps = [ cowlib ranch ];
    };

    cowboy_telemetry = buildRebar3 rec {
      name = "cowboy_telemetry";
      version = "0.4.0";

      src = fetchHex {
        pkg = "cowboy_telemetry";
        version = "${version}";
        sha256 = "7d98bac1ee4565d31b62d59f8823dfd8356a169e7fcbb83831b8a5397404c9de";
      };

      beamDeps = [ cowboy telemetry ];
    };

    cowlib = buildRebar3 rec {
      name = "cowlib";
      version = "2.17.1";

      src = fetchHex {
        pkg = "cowlib";
        version = "${version}";
        sha256 = "ff08bd17e6dd931445b18af77315b9b5fe052407110964ad2588c686b57b5e3f";
      };

      beamDeps = [];
    };

    hackney = buildRebar3 rec {
      name = "hackney";
      version = "1.25.0";

      src = fetchHex {
        pkg = "hackney";
        version = "${version}";
        sha256 = "7209bfd75fd1f42467211ff8f59ea74d6f2a9e81cbcee95a56711ee79fd6b1d4";
      };

      beamDeps = [ certifi idna metrics mimerl parse_trans ssl_verify_fun unicode_util_compat ];
    };

    httpoison = buildMix rec {
      name = "httpoison";
      version = "2.3.0";

      src = fetchHex {
        pkg = "httpoison";
        version = "${version}";
        sha256 = "d388ee70be56d31a901e333dbcdab3682d356f651f93cf492ba9f06056436a2c";
      };

      beamDeps = [ hackney ];
    };

    idna = buildRebar3 rec {
      name = "idna";
      version = "6.1.1";

      src = fetchHex {
        pkg = "idna";
        version = "${version}";
        sha256 = "92376eb7894412ed19ac475e4a86f7b413c1b9fbb5bd16dccd57934157944cea";
      };

      beamDeps = [ unicode_util_compat ];
    };

    jason = buildMix rec {
      name = "jason";
      version = "1.4.5";

      src = fetchHex {
        pkg = "jason";
        version = "${version}";
        sha256 = "b0c823996102bcd0239b3c2444eb00409b72f6a140c1950bc8b457d836b30684";
      };

      beamDeps = [];
    };

    metrics = buildRebar3 rec {
      name = "metrics";
      version = "1.0.1";

      src = fetchHex {
        pkg = "metrics";
        version = "${version}";
        sha256 = "69b09adddc4f74a40716ae54d140f93beb0fb8978d8636eaded0c31b6f099f16";
      };

      beamDeps = [];
    };

    mime = buildMix rec {
      name = "mime";
      version = "2.0.7";

      src = fetchHex {
        pkg = "mime";
        version = "${version}";
        sha256 = "6171188e399ee16023ffc5b76ce445eb6d9672e2e241d2df6050f3c771e80ccd";
      };

      beamDeps = [];
    };

    mimerl = buildRebar3 rec {
      name = "mimerl";
      version = "1.5.0";

      src = fetchHex {
        pkg = "mimerl";
        version = "${version}";
        sha256 = "db648ce065bae14ea84ca8b5dd123f42f49417cef693541110bf6f9e9be9ecc4";
      };

      beamDeps = [];
    };

    parse_trans = buildRebar3 rec {
      name = "parse_trans";
      version = "3.4.1";

      src = fetchHex {
        pkg = "parse_trans";
        version = "${version}";
        sha256 = "620a406ce75dada827b82e453c19cf06776be266f5a67cff34e1ef2cbb60e49a";
      };

      beamDeps = [];
    };

    plug = buildMix rec {
      name = "plug";
      version = "1.19.2";

      src = fetchHex {
        pkg = "plug";
        version = "${version}";
        sha256 = "b6fce20a56af5e60fa5dfecf3f907bb98ec981be43c79a3809a499bc3d133de0";
      };

      beamDeps = [ mime plug_crypto telemetry ];
    };

    plug_cowboy = buildMix rec {
      name = "plug_cowboy";
      version = "2.8.1";

      src = fetchHex {
        pkg = "plug_cowboy";
        version = "${version}";
        sha256 = "4c200288673d5bc86a0ab7dc6a2a069176a74e5d573ef62740a1c517458a5f26";
      };

      beamDeps = [ cowboy cowboy_telemetry plug ];
    };

    plug_crypto = buildMix rec {
      name = "plug_crypto";
      version = "2.1.1";

      src = fetchHex {
        pkg = "plug_crypto";
        version = "${version}";
        sha256 = "6470bce6ffe41c8bd497612ffde1a7e4af67f36a15eea5f921af71cf3e11247c";
      };

      beamDeps = [];
    };

    ranch = buildRebar3 rec {
      name = "ranch";
      version = "1.8.1";

      src = fetchHex {
        pkg = "ranch";
        version = "${version}";
        sha256 = "aed58910f4e21deea992a67bf51632b6d60114895eb03bb392bb733064594dd0";
      };

      beamDeps = [];
    };

    ssl_verify_fun = buildRebar3 rec {
      name = "ssl_verify_fun";
      version = "1.1.7";

      src = fetchHex {
        pkg = "ssl_verify_fun";
        version = "${version}";
        sha256 = "fe4c190e8f37401d30167c8c405eda19469f34577987c76dde613e838bbc67f8";
      };

      beamDeps = [];
    };

    stream_data = buildMix rec {
      name = "stream_data";
      version = "1.3.0";

      src = fetchHex {
        pkg = "stream_data";
        version = "${version}";
        sha256 = "3cc552e286e817dca43c98044c706eec9318083a1480c52ae2688b08e2936e3c";
      };

      beamDeps = [];
    };

    telemetry = buildRebar3 rec {
      name = "telemetry";
      version = "1.4.2";

      src = fetchHex {
        pkg = "telemetry";
        version = "${version}";
        sha256 = "928f6495066506077862c0d1646609eed891a4326bee3126ba54b60af61febb1";
      };

      beamDeps = [];
    };

    tesla = buildMix rec {
      name = "tesla";
      version = "1.20.0";

      src = fetchHex {
        pkg = "tesla";
        version = "${version}";
        sha256 = "3ecb41cb458772332752c3acdfe983e23abb991f5a43cfd69a64e9ea3f4b0061";
      };

      beamDeps = [ hackney jason mime telemetry ];
    };

    unicode_util_compat = buildRebar3 rec {
      name = "unicode_util_compat";
      version = "0.7.1";

      src = fetchHex {
        pkg = "unicode_util_compat";
        version = "${version}";
        sha256 = "b3a917854ce3ae233619744ad1e0102e05673136776fb2fa76234f3e03b23642";
      };

      beamDeps = [];
    };

    wallaby = buildMix rec {
      name = "wallaby";
      version = "0.30.12";

      src = fetchHex {
        pkg = "wallaby";
        version = "${version}";
        sha256 = "03b33244213b53af7c7e354a6ce129b1ffec9c57cac613eb76543f1fd46fcf70";
      };

      beamDeps = [ httpoison jason web_driver_client ];
    };

    web_driver_client = buildMix rec {
      name = "web_driver_client";
      version = "0.2.0";

      src = fetchHex {
        pkg = "web_driver_client";
        version = "${version}";
        sha256 = "83cc6092bc3e74926d1c8455f0ce927d5d1d36707b74d9a65e38c084aab0350f";
      };

      beamDeps = [ hackney jason tesla ];
    };
  };
in self

