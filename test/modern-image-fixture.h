#ifndef TLINK_MODERN_IMAGE_FIXTURE_H
#define TLINK_MODERN_IMAGE_FIXTURE_H
namespace cv {
struct Rect {int x,y,width,height;Rect(int px,int py,int w,int h):x(px),y(py),width(w),height(h){}};
struct Mat {
    int cols=0,rows=0;std::vector<unsigned char> bytes;
    Mat()=default;Mat(int w,int h):cols(w),rows(h),bytes(size_t(w)*h){}
    Mat operator()(Rect rect)const{
        assert(rect.x>=0&&rect.y>=0&&rect.x+rect.width<=cols&&rect.y+rect.height<=rows);
        Mat result(rect.width,rect.height);
        for(int y=0;y<rect.height;++y)for(int x=0;x<rect.width;++x)result.bytes[size_t(y)*rect.width+x]=bytes[size_t(y+rect.y)*cols+x+rect.x];
        return result;
    }
    bool empty()const{return bytes.empty();}
    template<class T>const T *ptr(int row)const{return reinterpret_cast<const T *>(bytes.data()+size_t(row)*cols);}
};
}
using cv::Mat;
static int cvRound(double value){return int(std::nearbyint(value));}
namespace cv {
struct Size{Size(int,int){}};enum{INTER_AREA,INTER_LINEAR};
static unsigned resizes=0;
static void resize(const Mat &input,Mat &out,Size,double x,double y,int){
    ++resizes;Mat result(cvRound(input.cols*x),cvRound(input.rows*y));
    for(int row=0;row<result.rows;++row)for(int col=0;col<result.cols;++col)
        result.bytes[size_t(row)*result.cols+col]=input.bytes[size_t(std::min(input.rows-1,int(row/y)))*input.cols+std::min(input.cols-1,int(col/x))];
    out=std::move(result);
}
}
#endif
