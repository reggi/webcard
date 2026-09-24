import release from "./release.generated.json";

const repositoryUrl = "https://github.com/reggi/webcard";

function DownloadIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20">
      <path d="M10 2v10m0 0 4-4m-4 4L6 8M3 14v2a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-2" />
    </svg>
  );
}

function Screenshot({ src, alt, className = "" }) {
  return (
    <div className={`screenshot-frame ${className}`}>
      <img src={src} alt={alt} loading="lazy" />
    </div>
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
        <div className="nav-links">
          <a href={repositoryUrl}>GitHub</a>
          <a className="nav-download" href={release.downloadUrl}>
            Download
          </a>
        </div>
      </nav>

      <section className="hero" id="top">
        <div className="hero-glow hero-glow-one" />
        <div className="hero-glow hero-glow-two" />
        <div className="hero-copy">
          <div className="eyebrow">
            <span />
            Native macOS app
          </div>
          <h1>Save the web as files you own.</h1>
          <p className="hero-description">
            Webcard turns rich website previews into portable <code>.webcard</code>{" "}
            files you can open, organize, refresh, and keep on your Mac.
          </p>
          <div className="hero-actions">
            <a className="download-button" href={release.downloadUrl}>
              <DownloadIcon />
              Download for macOS
            </a>
            <span className="requirement">Requires macOS 14 or later</span>
          </div>
        </div>

        <Screenshot
          className="hero-screenshot"
          src="./screenshots/directory-overview.webp"
          alt="Webcard showing a directory of saved website cards"
        />
      </section>

      <section className="file-story">
        <div className="section-copy">
          <span className="section-label">One link. One file.</span>
          <h2>Every card stands on its own.</h2>
          <p>
            A webcard keeps its image, title, description, URL, and capture
            history together in one portable file.
          </p>
        </div>
        <div className="card-wall" aria-label="Examples of individual webcards">
          <Screenshot
            className="card-shot card-shot-one"
            src="./screenshots/card-unsplash.webp"
            alt="An Unsplash page saved as a single webcard"
          />
          <Screenshot
            className="card-shot card-shot-two"
            src="./screenshots/card-city-hall.webp"
            alt="An Atlas Obscura page saved as a single webcard"
          />
          <Screenshot
            className="card-shot card-shot-three"
            src="./screenshots/card-command-module.webp"
            alt="A Smithsonian page saved as a single webcard"
          />
        </div>
      </section>

      <section className="library-story">
        <div className="section-copy centered">
          <span className="section-label">Folders become libraries</span>
          <h2>Browse your collection without giving up the filesystem.</h2>
          <p>
            Open any folder of webcards to search, browse nested folders, and
            switch naturally between compact and expansive layouts.
          </p>
        </div>
        <div className="library-stack">
          <Screenshot
            className="library-shot library-shot-back"
            src="./screenshots/directory-code-food.webp"
            alt="A Webcard directory showing code and food collections"
          />
          <Screenshot
            className="library-shot library-shot-front"
            src="./screenshots/directory-birds.webp"
            alt="A Webcard directory showing a collection of bird cards"
          />
        </div>
      </section>

      <section className="native-story">
        <div className="native-copy">
          <span className="section-label">Native all the way through</span>
          <h2>Your cards belong in Finder.</h2>
          <p>
            Custom file icons and previews make every webcard recognizable
            before you open it. Move, rename, group, and back up your collection
            like any other files on your Mac.
          </p>
          <ul>
            <li>Custom file icons</li>
            <li>Finder thumbnails</li>
            <li>Quick Look previews</li>
          </ul>
        </div>
        <div className="finder-shots">
          <Screenshot
            src="./screenshots/finder-icons.webp"
            alt="Webcard files displayed with image thumbnails in Finder"
          />
          <Screenshot
            className="finder-list"
            src="./screenshots/finder-list.webp"
            alt="Webcard files displayed in Finder list view"
          />
        </div>
      </section>

      <section className="quick-look-story">
        <div className="section-copy centered">
          <span className="section-label">Quick Look built in</span>
          <h2>Preview a card without opening it.</h2>
          <p>
            Press the Space bar in Finder to see the saved image and metadata
            instantly. Quick Look reads the file locally without contacting the
            original website.
          </p>
        </div>
        <div className="quick-look-wall" aria-label="Quick Look previews of webcard files">
          <Screenshot
            className="quick-look-shot quick-look-node"
            src="./screenshots/quick-look-node.webp"
            alt="A GitHub webcard displayed in the macOS Quick Look window"
          />
          <Screenshot
            className="quick-look-shot quick-look-bird"
            src="./screenshots/quick-look-bird.webp"
            alt="A bird webcard displayed in the macOS Quick Look window"
          />
          <Screenshot
            className="quick-look-shot quick-look-pizza"
            src="./screenshots/quick-look-pizza.webp"
            alt="A pizza recipe webcard displayed in the macOS Quick Look window"
          />
        </div>
      </section>

      <section className="start-story">
        <Screenshot
          className="start-screenshot"
          src="./screenshots/start-screen.webp"
          alt="The Webcard start screen with options to create, import, open, or drop files"
        />
        <div className="start-copy">
          <span className="section-label">Start anywhere</span>
          <h2>Create one card or import a whole list.</h2>
          <p>
            Paste a URL, import several addresses, open an existing folder, or
            drag files directly into the app.
          </p>
        </div>
      </section>

      <section className="download-panel">
        <img src="./app-icon.png" alt="" />
        <div>
          <span>Webcard for macOS</span>
          <h2>Keep the web cards worth saving.</h2>
        </div>
        <a className="download-button light" href={release.downloadUrl}>
          <DownloadIcon />
          Download latest release
        </a>
      </section>

      <footer>
        <a className="brand footer-brand" href="#top">
          <img src="./app-icon.png" alt="" />
          <span>Webcard</span>
        </a>
        <p>Native, private, and made for macOS.</p>
        <a href={repositoryUrl}>GitHub</a>
      </footer>
    </main>
  );
}
