const releaseUrl = "https://github.com/reggi/webcard/releases/latest";

function DownloadIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20">
      <path d="M10 2v10m0 0 4-4m-4 4L6 8M3 14v2a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-2" />
    </svg>
  );
}

function FolderIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M3.5 7.5a2 2 0 0 1 2-2h4l2 2h7a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2v-9Z" />
    </svg>
  );
}

function RefreshIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M19 8a8 8 0 1 0 .7 7.2M19 4v4h-4" />
    </svg>
  );
}

function ClockIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="8.5" />
      <path d="M12 7.5V12l3 2" />
    </svg>
  );
}

function Feature({ icon, title, children }) {
  return (
    <article className="feature">
      <div className="feature-icon">{icon}</div>
      <h2>{title}</h2>
      <p>{children}</p>
    </article>
  );
}

export default function App() {
  return (
    <main>
      <nav className="nav" aria-label="Primary navigation">
        <a className="brand" href="#top" aria-label="Webcard home">
          <img src="./app-icon.png" alt="" />
          <span>Webcard</span>
        </a>
        <a className="nav-download" href={releaseUrl}>
          Download
        </a>
      </nav>

      <section className="hero" id="top">
        <div className="ambient ambient-one" />
        <div className="ambient ambient-two" />
        <div className="hero-copy">
          <div className="eyebrow">
            <span className="apple-mark">●</span>
            Built for macOS
          </div>
          <h1>Keep the web cards worth saving.</h1>
          <p className="hero-description">
            Webcard turns rich website previews into portable files you can open,
            organize, refresh, and revisit on your Mac.
          </p>
          <div className="hero-actions">
            <a className="download-button" href={releaseUrl}>
              <DownloadIcon />
              Download for macOS
            </a>
            <span className="requirement">Requires macOS 14 or later</span>
          </div>
        </div>

        <div className="app-showcase" aria-label="Webcard app preview">
          <div className="app-icon-wrap">
            <img src="./app-icon.png" alt="Webcard app icon" />
          </div>
          <div className="window">
            <div className="titlebar">
              <div className="traffic-lights">
                <span />
                <span />
                <span />
              </div>
              <span className="window-title">Webcard</span>
            </div>
            <div className="window-content">
              <div className="saved-card">
                <div className="card-image">
                  <span className="card-orbit orbit-one" />
                  <span className="card-orbit orbit-two" />
                  <img src="./app-icon.png" alt="" />
                </div>
                <div className="card-copy">
                  <span className="site-label">WEBCARD</span>
                  <strong>Your favorite corner of the web</strong>
                  <p>Saved with its image, details, and history ready whenever you need it.</p>
                  <span className="fake-link">webcard.app</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section className="features" aria-labelledby="features-title">
        <div className="section-heading">
          <span>Made for your Mac</span>
          <h2 id="features-title">A home for every webcard.</h2>
        </div>
        <div className="feature-grid">
          <Feature icon={<FolderIcon />} title="Files you own">
            Each webcard is a portable file. Keep it in Finder, move it into a
            folder, or share it like any other document.
          </Feature>
          <Feature icon={<RefreshIcon />} title="Refresh on demand">
            Update a saved card only when you choose. Webcard never changes your
            files or contacts a site in the background.
          </Feature>
          <Feature icon={<ClockIcon />} title="Built in history">
            Keep dated captures together and return to an earlier version without
            losing what came before.
          </Feature>
        </div>
      </section>

      <section className="download-panel">
        <img src="./app-icon.png" alt="" />
        <div>
          <span>Webcard for macOS</span>
          <h2>Save the web as a file.</h2>
        </div>
        <a className="download-button light" href={releaseUrl}>
          <DownloadIcon />
          Latest release
        </a>
      </section>

      <footer>
        <a className="brand footer-brand" href="#top">
          <img src="./app-icon.png" alt="" />
          <span>Webcard</span>
        </a>
        <p>Native, private, and made for macOS.</p>
        <a href="https://github.com/reggi/webcard">GitHub</a>
      </footer>
    </main>
  );
}
