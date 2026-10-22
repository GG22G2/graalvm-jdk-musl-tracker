public class Loc {
    public static void main(String[] args) {
        System.out.println("中文输出测试 ABC");
        System.out.println("file.encoding    = " + System.getProperty("file.encoding"));
        System.out.println("stdout.encoding  = " + System.getProperty("stdout.encoding"));
        System.out.println("stderr.encoding  = " + System.getProperty("stderr.encoding"));
        System.out.println("native.encoding  = " + System.getProperty("native.encoding"));
        System.out.println("sun.jnu.encoding = " + System.getProperty("sun.jnu.encoding"));
        System.out.println("user.language    = " + System.getProperty("user.language"));
        java.io.File f = new java.io.File("中文文件名.txt");
        System.out.println("filename roundtrip = " + f.getName());
        try {
            f.createNewFile();
            System.out.println("create zh file     = " + f.exists() + " len=" + f.getName().length());
        } catch (Exception e) {
            System.out.println("create zh file     = FAILED " + e);
        }
    }
}
