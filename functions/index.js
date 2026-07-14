const functions = require("firebase-functions");
const axios = require("axios");
const cors = require("cors")({ origin: true });

const FASTMOSS_APP_ID = "finmatrix";
const FASTMOSS_APP_SECRET = "okwbxiwkvbohbcztkodiamioxzrsfudf";
const UPSTREAM = "https://openapi.fastmoss.com";

exports.proxy = functions.https.onRequest((req, res) => {
  return cors(req, res, async () => {
    if (req.method === "OPTIONS") {
      return res.status(204).send();
    }

    if (req.method !== "POST") {
      return res.status(405).json({ code: -1, message: "POST only" });
    }

    const path = req.path.replace(/^\/proxy/, "");

    // Safety check for allowed paths (same as original worker)
    const ALLOWED_PATHS = [
      "/product/v1/rank/topSelling",
      "/product/v1/rank/fullyManaged",
      "/shop/v1/rank/topSelling",
      "/shop/v1/rank/fullyManaged",
    ];

    if (!ALLOWED_PATHS.includes(path)) {
      return res.status(404).json({ code: -1, message: `path not allowed: ${path}` });
    }

    try {
      const response = await axios({
        method: "POST",
        url: `${UPSTREAM}${path}`,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "Authorization": `Bearer ${FASTMOSS_APP_SECRET}`,
          "access-key": FASTMOSS_APP_ID,
        },
        data: req.body,
      });

      res.set("Cache-Control", "public, max-age=1800");
      return res.status(response.status).json(response.data);
    } catch (error) {
      console.error("Proxy Error:", error.response ? error.response.data : error.message);
      const status = error.response ? error.response.status : 500;
      const data = error.response ? error.response.data : { code: -1, message: error.message };
      return res.status(status).json(data);
    }
  });
});
