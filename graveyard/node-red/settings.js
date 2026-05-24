module.exports = {
  credentialSecret: process.env.NODE_RED_CREDENTIAL_SECRET,

  adminAuth: {
    type: "credentials",
    users: [{
      username: process.env.NODE_RED_USER,
      password: process.env.NODE_RED_PASSWORD_HASH,
      permissions: "*"
    }]
  },
  httpAdminRoot: "/admin",
  httpNodeRoot: "/",
  ui: { path: "ui" },
  functionGlobalContext: {}
};
