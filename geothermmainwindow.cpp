#include "geothermmainwindow.h"
#include "./ui_geothermmainwindow.h"
#include "./aboutdialog.h"
#include "QMessageBox"
#include "QFileDialog"
#include "embedding.h"
#include <iostream>

using namespace std;

bool compModuleLoaded = false;
QString appRoot = "/home/eugeneai/projects/code/dymsh";


GeothermMainWindow::GeothermMainWindow(QWidget *parent)
    : QMainWindow(parent)
    , ui(new Ui::GeothermMainWindow)
{
    ui->setupUi(this);
    csvModel = new QCSVModel();
    gtModel = new QGTModel();
    reloadReport();
}

void GeothermMainWindow::actionAbout() {
    AboutDialog a ;
    a.exec();
}

GeothermMainWindow::~GeothermMainWindow()
{
    delete gtModel;
    delete csvModel;
    delete ui;
}

void GeothermMainWindow::on_pushButton_2_clicked()
{
    QString csvFileName = ui->dataFileName->text();
    if (csvFileName=="") {
        QMessageBox::information(this, "No file were chosen",
                                 QString("File name, You have chosen appears to be '%1'").arg(csvFileName));
        return;
    }
    if (loadCompModule()) {
        jl_value_t *ret = handleEval(QString("userDF=userLoadCSV(\"%1\")").arg(csvFileName));
        if (ret != nullptr) {
            csvModel->setDataFrame(ret);
            ui->csvView->setModel(csvModel);
        }
    } else {
        QMessageBox::critical(this, "Cannot load Julia module",
            "Cannot load Julia module, probably a syntax error, check the stdout.");

    }
}

void GeothermMainWindow::on_pushButton_clicked()
{
    // QMessageBox::information(this, "Clicked", "Button Clicked");
    QString csvFileName = QFileDialog::getOpenFileName(this, "Choose a CSV file of measurements",
                                                       QString("%1/data").arg(appRoot),
                                                       tr("CSV files (*.csv)"));
    ui->dataFileName->setText(csvFileName);
    on_pushButton_2_clicked();
}

// -----------------------------------------------------------

jl_value_t * QDataFrameModel::setDataFrame(jl_value_t * df) {
    beginResetModel();
    dataFrame = df;
    endResetModel();
    return df;
}

QModelIndex QDataFrameModel::index(int row, int column,
                             const QModelIndex &parent) const {
    Q_UNUSED(parent);
    return createIndex(row,column,nullptr);
}

QModelIndex QDataFrameModel::parent(const QModelIndex &index) const {
    return createIndex(-1,-1);
}

// --------- QCSVModel -------------------------------------

QVariant QCSVModel::data(const QModelIndex &index, int role) const {
    if (! index.isValid()) return QVariant();
    if (role == Qt::DisplayRole && dataFrame != nullptr) {
        int row = index.row();
        int col = index.column();
        QString cmd("string(userDF[%1,%2])");
        QString ncmd = cmd.arg(row+1).arg(col+1); // Long live, Julia!
        jl_value_t * ret = handleEval(ncmd);
        if (ret != nullptr) {
            return QString(jl_string_ptr(ret));
        } else {
            return QString("cannot show '%1'").arg(ncmd);
        }
    } else {
        return QVariant();
    }
}

QVariant QCSVModel::headerData(int section, Qt::Orientation orientation, int role) const {
    if (role != Qt::DisplayRole)
        return QVariant();

    if (orientation == Qt::Horizontal) {
        jl_value_t * ret = handleEval(QString("names(userDF)[%1]").arg(section+1));
        if (ret != nullptr) {
            QString name(jl_string_ptr(ret));
            QString mname = name.replace("_",", ");
            return mname;
        }
        return QString("Column %1").arg(section);
    } else
        return QString("%1").arg(section+1);
}

int QCSVModel::columnCount(const QModelIndex &parent) const {
    Q_UNUSED(parent);
    if (dataFrame != nullptr) {
        jl_value_t * ret = handleEval("size(userDF,2)");
        return jl_unbox_int64(ret);
    } else return 10;
}
int QCSVModel::rowCount (const QModelIndex &parent) const {
    Q_UNUSED(parent);
    if (dataFrame != nullptr) {
        jl_value_t * ret = handleEval("size(userDF,1)");
        return jl_unbox_int64(ret);
    } else return 1;
}


// ----------------GT Moel -------------------------------------


QVariant QGTModel::data(const QModelIndex &index, int role) const {
    if (! index.isValid()) return QVariant();
    if (role == Qt::DisplayRole && isValid()) {
        jl_value_t * ret = nullptr;
        int row = index.row();
        int col = index.column();
        if (col == 0) {
            ret = handleEval(QString("string(userResult.GT[1].z[%1])").arg(row+1));
            if (ret != nullptr) {
                return QString(jl_string_ptr(ret));
            } else {
                return QString("bad z");
            }
        }
        QString cmd("string(userResult.GT[%2].T[%1])");
        QString ncmd = cmd.arg(row+1).arg(col); // Long live, Julia!
        ret = handleEval(ncmd);
        if (ret != nullptr) {
            return QString(jl_string_ptr(ret));
        } else {
            return QString("cannot show '%1'").arg(ncmd);
        }
    } else {
        return QVariant();
    }
}

QVariant QGTModel::headerData(int section, Qt::Orientation orientation, int role) const {
    if (role != Qt::DisplayRole)
        return QVariant();

    if (orientation == Qt::Horizontal) {
        if (isValid()) {
            if (section==0) return "z";
            QString cmd("string(userResult.GT[%1].label)");
            QString ncmd = cmd.arg(section); // Long live, Julia!
            jl_value_t * ret = handleEval(ncmd);
            if (ret != nullptr) {
                return QString(jl_string_ptr(ret));
            } else {
                return QString("cannot show '%1'").arg(ncmd);
            }
        }
        return QString("Column %1").arg(section);
    } else
        return QString("%1").arg(section+1);
}

int QGTModel::columnCount(const QModelIndex &parent) const {
    Q_UNUSED(parent);
    if (isValid()) {
        jl_value_t * ret = handleEval("size(userResult.GT,1)+1");
        if (ret!=nullptr) {
            return jl_unbox_int64(ret);
        } else {
            return 1;
        }
    } else return 10;
}
int QGTModel::rowCount (const QModelIndex &parent) const {
    Q_UNUSED(parent);
    if (dataFrame != nullptr) {
        jl_value_t * ret = handleEval("size(userResult.GT[1].z,1)");
        if (ret!=nullptr) {
            return jl_unbox_int64(ret);
        } else {
            return 0;
        }
    } else return 1;
}

// --------------------------------------------------------------

jl_value_t * handleEval(QString cmd) {
    jl_value_t * ret = nullptr;
    if (! compModuleLoaded) {
        if (!loadCompModule ())
            return ret;
    }
    ret = handle_eval_string(cmd.toStdString().c_str());
    if (ret != nullptr) {
        jl_call1(jl_get_function(jl_base_module, "show"), ret);
    } else {
        cout << "Julia command evaluation failed.\n";
    }
    cout.flush();
    return ret;
}

bool loadCompModule() {
    if (compModuleLoaded) {
        return true;
        cout << "Julia runtaime have been already loaded" << endl;
    }
    QString incString = QString("include(\"%1/computegterm.jl\")").arg(appRoot);
        if (handle_eval_string(incString.toStdString().c_str())!=nullptr) {
        cout << "Julia runtime successfully loaded.\n";
        compModuleLoaded = true;
    } else {
        cout << "Julia runtime loading failed.\n";
        compModuleLoaded = false;
    }
    cout.flush();
    jl_value_t * ret = handleEval(QString("appRoot=\"%1\"").arg(appRoot));
    if (ret==nullptr) {
        QMessageBox::critical(nullptr, "Cannot set epplication root", "Something wrong with syntax");
    };
    return compModuleLoaded;
}


void GeothermMainWindow::on_calcPushButton_clicked()
{
    if (! csvModel->isValid()) {
        QMessageBox::critical(this,
                              "You did not load data!",
                              "In order to proceed with a compresesive computations, one must load an input deta. Proceeding to the page..");
        ui->views->setCurrentIndex(0);
        return;
    }
    if (! checkInitialData()) {
        QMessageBox::critical(this,
                              "Initial data is wrong",
                              "Check syntax of all the expressions. Hints are available (mouse hover for 5 seconds).");
        return;
    }
    jl_value_t * ret = handleEval("userResult=userComputeGeotherm(userInit, userDF)");
    if (ret == nullptr) {
        QMessageBox::critical(this,
                              "Calculation failded!",
                              "There is a problem with calculations, no results were obtained, see log!");
        return;
    }
    gtModel->setDataFrame(ret);
    ui->csvResultView->setModel(gtModel);
    ret = handleEval("userPlot(userResult)");
    if (ret==nullptr) {
        QMessageBox::critical(this,
                              "Plotting failded!",
                              "There is a problem with plotting, results are obtained, but plots not, see log!");
        // return;
    }
    reloadReport();
    ui->views->setCurrentIndex(3);
}


void GeothermMainWindow::on_pushButton_3_clicked()
{
    if(! checkInitialData()) {
        QMessageBox::critical(this,
                              "Initial data is wrong",
                              "Check syntax of all the expressions. Hints are available (mouse hover for 5 seconds).");
    } else {
        QMessageBox::information(this,
                                 "The initial data syntax are ok!", "Now You can safely press 'Calculate' button!");
    }
}

QString GeothermMainWindow::constructInitialExpr() {
    QString exprtmpl("userInit=GTInit(%1, %2, %3, %4, %5, %6, %7, %8, %9)");
    QString optCh;
    if (ui->opt->checkState()==Qt::Checked) {
        optCh="true";
    } else {
        optCh="false";
    }
    QString expr = exprtmpl
                       .arg(ui->q0->text()) //1
                       .arg(ui->D->text()) //2
                       .arg(ui->Zbot->text()) //3
                       .arg(ui->Zmax->text()) //4
                       .arg(ui->Dz->text()) //5
                       .arg(ui->P->text()) //6
                       .arg(ui->H->text()) //7
                       .arg(ui->iref->text()) //8
                       .arg(optCh);//9
    return expr;
}

bool GeothermMainWindow::checkInitialData() {
    QString expr = constructInitialExpr();
    jl_value_t * ret = handleEval(expr);
    return ret != nullptr;
}

void GeothermMainWindow::reloadReport() {
    //QUrl u = QUrl::fromUserInput("https://edu.irnok.net/");
    QFile ifile(QString("%1/report.html").arg(appRoot));
    if (!ifile.open(QFile::ReadOnly | QFile::Text)) {
        QMessageBox::critical(this,
                              "Cannot load report template!",
                              "Something wrong with report page template (report.html).");
        return;
    }
    QTextStream i(&ifile);
    QString content(i.readAll());

    QUrl u = QUrl::fromUserInput(QString("file:%1/geotherm.svg").arg(appRoot));
    ui->webPage->setUrl(u);
    /*
    QString gtURL = QString("file:%1/geotherm.svg").arg(appRoot);
    QString interpContent = QString(content).arg(gtURL);
    cout << endl << (interpContent.toStdString()) << endl;
    ui->webPage->setHtml(interpContent);
    */
}
