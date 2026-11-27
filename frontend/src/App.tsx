import { Link } from "react-router-dom";

export default function App({ testsEnabled }: { testsEnabled: boolean }) {
  return <main>
    <h1>Musicflows</h1>
    <p>アプリケーション準備中</p>
    {testsEnabled && <nav aria-label="開発用画面"><ul>
      <li><Link to="/dev/db-test">DB疎通確認</Link></li>
      <li><Link to="/auth-test">認証疎通確認</Link></li>
      <li><Link to="/jobtest">ジョブ疎通確認</Link></li>
    </ul></nav>}
  </main>;
}
